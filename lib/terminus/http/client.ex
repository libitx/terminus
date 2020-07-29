defmodule Terminus.HTTP.Client do
  @moduledoc """
  A `GenStage` producer module for creating streaming HTTP requests.
  Each request is a GenStage process, enabling creating powerful concurrent
  data flows.

  ## Usage

      # Create the connection process
      iex> Terminus.HTTP.Client.connect("http://x.bitfs.network")
      {:ok, pid}

      # Begin a request
      iex> Terminus.HTTP.Client.request(pid, "GET", path)
      :ok

      # Stream the result
      iex> GenStage.stream([{pid, cancel: :transient}])
      %Stream{}
  """
  require Logger
  use GenStage
  alias Terminus.HTTP.{Request,Response}
  alias Mint.{HTTP,HTTP2}


  defstruct conn: nil,
            status: 0,
            request_ref: nil,
            request: %Request{},
            response: %Response{},
            last_event_id: nil,
            events: [],
            demand: 0,
            decoder: :raw,
            recycle_after: nil,
            recycle_ref: nil


  @typedoc "Terminus HTTP State."
  @type t :: %__MODULE__{
    conn: Mint.HTTP.t,
    status: status,
    request_ref: reference,
    request: Request.t,
    response: Response.t,
    last_event_id: String.t,
    events: list,
    demand: integer,
    decoder: atom,
    recycle_after: integer | nil,
    recycle_ref: reference
  }

  @typedoc """
  HTTP request status.

  * `0` - Connecting
  * `1` - Connected
  * `2` - Closed
  """
  @type status :: 0 | 1 | 2


  @doc """
  Creates a new connection to a given server and returns a GenStage [`pid`](`t:pid/0`).

  ## Options

  The accepted options are:

  * `:decoder` - Request body binary.
  * `:recycle_after` - Number of seconds after which the request should be recycled if it has recieved no events (used in EventSource connections).
  """
  @spec connect(String.t, keyword) :: {:ok, pid} | {:error, Exception.t}
  def connect(base_url, options \\ []) do
    case Keyword.get(options, :stage) do
      true ->
        start_link(base_url, options)
      _ ->
        start(base_url, options)
    end
  end


  @doc """
  Starts the client process without links (outside of a supervision tree).
  """
  @spec start(String.t, keyword) :: {:ok, pid} | {:error, Exception.t}
  def start(base_url, options \\ []) do
    GenStage.start(__MODULE__, {base_url, options})
  end


  @doc """
  Starts a client process linked to the current process.

  This is often used to start the client process as part of a supervision tree.
  """
  @spec start_link(String.t, keyword) :: {:ok, pid} | {:error, Exception.t}
  def start_link(base_url, options \\ []) do
    GenStage.start_link(__MODULE__, {base_url, options})
  end


  @doc """
  Sends a request to the connected server.

  The function is asynchronous and returns `:ok`. The GenStage [`pid`](`t:pid/0`)
  can be subscribed to to listen to streaming data chunks.

  ## Options

  The accepted options are:

  * `:headers` - List of HTTP headers in tuple form.
  * `:body` - Request body binary.
  * `:token` - If provided, sets the `Token` HTTP header.
  * `:last_event_id` - Used with EventSource connections. If provided, sets the `Last-Event-ID` header.
  """
  @spec request(pid, String.t, String.t, keyword) :: :ok
  def request(pid, method, path, options \\ []) do
    GenStage.cast(pid, {:request, method, path, options})
  end


  @doc """
  Manually stops and restarts the client's current request.

  Alternatively, this can be automated by using the `:recycle_after` option
  when calling `connect/2`.
  """
  @spec recycle(pid) :: :ok
  def recycle(pid) do
    GenStage.cast(pid, :recycle)
  end


  @doc """
  Manually stops the Client process, closing it's HTTP request.
  """
  @spec close(pid) :: :ok
  def close(pid, reason \\ :shutdown) do
    GenStage.stop(pid, reason)
  end


  # Callbacks


  @impl true
  def init({base_url, options}) do
    %{scheme: scheme, host: host, port: port} = URI.parse(base_url)

    case HTTP.connect(String.to_atom(scheme), host, port) do
      {:ok, conn} ->
        params = options
        |> Keyword.take([:decoder, :recycle_after])
        |> Keyword.put(:conn, conn)

        {:producer, struct(__MODULE__, params)}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @impl true
  def handle_cast({:request, method, path, options}, state) do
    req = %Request{
      method: method,
      path: path,
      headers: Keyword.get(options, :headers, []),
      body: Keyword.get(options, :body)
    }

    req = update_in(req.headers, & put_token_header(&1, Keyword.get(options, :token)))
    req = update_in(req.headers, & put_last_event_id_header(&1, Keyword.get(options, :last_event_id)))
    state = put_in(state.request, req)

    case do_request({state.conn, req.method, req.path, req.headers, req.body}, state) do
      {:ok, state} ->
        {:noreply, [], state}

      {:error, reason, state} ->
        {:stop, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:recycle, state) do
    case do_recycle(state) do
      {:ok, state} ->
        {:noreply, [], state}

      {:error, reason, state} ->
        {:stop, {:error, reason}, state}
    end
  end


  # Handles initializing a new HTTP request
  defp do_request({conn, method, path, headers, body}, state) do
    case HTTP.request(conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = Map.merge(state, %{
          conn: conn,
          status: 1,
          request_ref: request_ref,
        })
        state = update_in(state.recycle_ref, & recycle_timer(&1, state.recycle_after))
        {:ok, state}

      {:error, conn, reason} ->
        state = Map.merge(state, %{
          conn: conn,
          status: 3
        })
        {:error, reason, state}
    end
  end


  # Handles recycling a running HTTP request
  defp do_recycle(%__MODULE__{request: req} = state) do
    case HTTP2.cancel_request(state.conn, state.request_ref) do
      {:ok, conn} ->
        do_request({conn, req.method, req.path, req.headers, req.body}, state)

      {:error, conn, reason} ->
        state = put_in(state.conn, conn)
        {:error, reason, state}
    end
  end


  # Puts the token into the headers
  defp put_token_header(headers, nil), do: headers
  defp put_token_header(headers, {app, key}),
    do: put_token_header(headers, Application.get_env(app, key))
  defp put_token_header(headers, token) when is_binary(token),
    do: List.keystore(headers, "token", 0, {"token", token})

  # Puts the Last Event ID into the headers
  defp put_last_event_id_header(headers, nil), do: headers
  defp put_last_event_id_header(headers, last_event_id),
    do: List.keystore(headers, "last-event-id", 0, {"last-event-id", last_event_id})

  # Refreshes the recycle timer
  defp recycle_timer(timer, nil), do: timer
  defp recycle_timer(timer, seconds)
    when is_reference(timer),
    do: Process.cancel_timer(timer) |> recycle_timer(seconds)
  defp recycle_timer(_timer, seconds)
    when is_integer(seconds) and seconds > 0,
    do: Process.send_after(self(), :recycle_request, seconds * 1000)


  @impl true
  def handle_demand(demand, state) do
    {events, state} = update_in(state.demand, & &1 + demand)
    |> take_demanded_events
    {:noreply, events, state}
  end


  @impl true
  def handle_info(:recycle_request, state) do
    Logger.info "Recycling #{__MODULE__}: #{state.conn.hostname} #{ inspect state.request_ref }"

    case do_recycle(state) do
      {:ok, state} ->
        {:noreply, [], state}

      {:error, reason, state} ->
        {:stop, {:error, reason}, state}
    end
  end


  @impl true
  def handle_info(:terminate_request, state) do
    close_connection(state)
  end


  @impl true
  def handle_info(message, state) do
    case HTTP.stream(state.conn, message) do
      :unknown ->
        Logger.warn("Received unknown message: " <> inspect(message))
        {:noreply, [], state}

      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = update_in(state.recycle_ref, & recycle_timer(&1, state.recycle_after))

        {events, state} = Enum.reduce(responses, state, &process_response/2)
        |> decode_response_data
        |> take_demanded_events

        if (state.status == 2 or state.conn.state == :closed),
          do: Process.send(self(), :terminate_request, [])

        {:noreply, events, state}

      {:error, conn, _error, _responses} ->
        state = Map.merge(state, %{
          conn: conn,
          status: 2
        })
        close_connection(state)
    end
  end


  # Processes the given response chunk and updates the state.
  defp process_response({:status, request_ref, status}, %__MODULE__{request_ref: ref} = state)
    when request_ref == ref,
    do: put_in(state.response.status, status)

  defp process_response({:headers, request_ref, headers}, %__MODULE__{request_ref: ref} = state)
    when request_ref == ref,
    do: update_in(state.response.headers, &(&1 ++ headers))

  defp process_response({:data, request_ref, data}, %__MODULE__{request_ref: ref} = state)
    when request_ref == ref,
    do: update_in(state.response.data, &(&1 <> data))

  defp process_response({:error, request_ref, reason}, %__MODULE__{request_ref: ref} = state)
    when request_ref == ref
  do
    Logger.error "Request error: #{ inspect reason }"
    put_in(state.status, 0)
  end

  defp process_response({:done, request_ref}, %__MODULE__{request_ref: ref} = state)
    when request_ref == ref,
    do: put_in(state.status, 2)


  # Handles decoding of response data chunks
  defp decode_response_data(%__MODULE__{response: response} = state) do
    {response, events} = Response.decode_data(response, as: state.decoder)

    Map.merge(state, %{
      response: response,
      events: state.events ++ events
    })
  end


  # Takes the demanded events from the state
  defp take_demanded_events(%__MODULE__{demand: demand} = state) do
    {events, remaining} = Enum.split(state.events, demand)

    state = update_in(state.demand, & &1 - length(events))
    |> Map.put(:events, remaining)

    {events, state}
  end


  # Handles closing the connecting, eiether with or without an Exception
  defp close_connection(%__MODULE__{response: response} = state) do
    if response.status in 200..299 do
      {:stop, :normal, state}
    else
      {:stop, %Terminus.HTTP.Error{status: response.status}, state}
    end
  end


  @impl true
  def terminate(reason, state) do
    Logger.debug("Terminating #{__MODULE__}: #{state.conn.hostname} #{inspect reason}")
    HTTP.close(state.conn)
  end

end
