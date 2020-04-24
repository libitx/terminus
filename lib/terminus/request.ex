defmodule Terminus.Request do
  @moduledoc """
  A `GenStage` producer module for creating streaming HTTP requests.

  Each request is a GenStage process, enabling creating powerful concurrent
  data flows.

  ## Usage

      # Create the connection process
      iex> Terminus.Request.connect(:https, host, 443)
      {:ok, pid}

      # Begin a request
      iex> Terminus.Request.request(pid, "GET", path, headers, body)
      :ok

      # Stream the result
      iex> GenStage.stream([{pid, cancel: :transient}])
      %Stream{}
  """
  use GenStage
  alias Mint.HTTP
  alias Terminus.{Chunker,HTTPError,Response}
  require Logger


  @typedoc "Streaming HTTP request state"
  @type t :: %__MODULE__{
    conn: map,
    ref: String.t,
    response: Response.t,
    events: list,
    demand: integer,
    chunker: atom,
    last_resp: atom
  }
  defstruct conn: nil,
            ref: nil,
            response: %Response{},
            events: [],
            demand: 0,
            chunker: :raw,
            last_resp: :init


  @doc """
  Creates a new connection to a given server and returns a GenStage [`pid`](`t:pid/0`).
  """
  @spec connect(atom, String.t, integer, keyword) :: {:ok, pid} | {:error, String.t}
  def connect(scheme, host, port, opts \\ []) do
    case Keyword.get(opts, :stage) do
      true ->
        GenStage.start_link(__MODULE__, {scheme, host, port})
      _ ->
        GenStage.start(__MODULE__, {scheme, host, port})
    end
  end


  @doc """
  Sends a request to the connected server.

  The function is asynchronous and returns `:ok`. The GenStage [`pid`](`t:pid/0`)
  can be subscribed to to listen to streaming data chunks.
  """
  @spec request(pid, String.t, String.t, list, String.t | nil, atom) :: :ok
  def request(pid, method, path, headers, body, chunker \\ :raw) do
    GenStage.cast(pid, {:request, method, path, headers, body, chunker})
  end


  ## Callbacks

  @impl true
  def init({scheme, host, port}) do
    case HTTP.connect(scheme, host, port) do
      {:ok, conn} ->
        state = %__MODULE__{conn: conn}
        {:producer, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @impl true
  def handle_cast({:request, method, path, headers, body, chunker}, state) do
    case HTTP.request(state.conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = Map.merge(state, %{
          conn: conn,
          ref: request_ref,
          chunker: chunker
        })
        {:noreply, [], state}

      {:error, conn, reason} ->
        state = put_in(state.conn, conn)
        {:reply, {:error, reason}, state}
    end
  end


  @impl true
  def handle_demand(demand, state) do
    {events, state} = update_in(state.demand, &(&1 + demand))
    |> process_events
    {:noreply, events, state}
  end


  @impl true
  def handle_info(_message, %__MODULE__{last_resp: :done} = state),
    do: process_end(state)

  def handle_info(message, state) do
    case HTTP.stream(state.conn, message) do
      :unknown ->
        Logger.warn("Received unknown message: " <> inspect(message))
        {:noreply, [], state}

      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        {events, state} = Enum.reduce(responses, state, &process_response/2)
        |> process_events

        case {events, state} do
          {[], %{last_resp: :done}} ->
            process_end(state)
          {[], %{conn: %{state: :closed}}} ->
            process_end(state)
          _ ->
            {:noreply, events, state}
        end

      {:error, conn, %Mint.TransportError{reason: :closed}, _responses} ->
        state = put_in(state.conn, conn)
        {:stop, :normal, state}

      {:error, conn, error, _responses} ->
        state = put_in(state.conn, conn)
        {:stop, error, state}
    end
  end


  # Processes the given response chunk and updates the state.
  defp process_response({:status, request_ref, status}, %__MODULE__{ref: ref} = state)
    when request_ref == ref
  do
    put_in(state.response.status, status)
    |> Map.put(:last_resp, :status)
  end

  defp process_response({:headers, request_ref, headers}, %__MODULE__{ref: ref} = state)
    when request_ref == ref
  do
    update_in(state.response.headers, &(&1 ++ headers))
    |> Map.put(:last_resp, :headers)
  end

  defp process_response({:data, request_ref, data}, %__MODULE__{ref: ref} = state)
    when request_ref == ref
  do
    update_in(state.response.data, &(&1 <> data))
    |> Map.put(:last_resp, :data)
  end

  defp process_response({:error, request_ref, reason}, %__MODULE__{ref: ref} = state)
    when request_ref == ref
  do
    Logger.error "Request error: #{ inspect reason }"
    put_in(state.last_resp, :error)
  end

  defp process_response({:done, request_ref}, %__MODULE__{ref: ref} = state)
    when request_ref == ref,
    do: put_in(state.last_resp, :done)


  # Processes the response data and chunks into events to provide to consumers.
  defp process_events(%__MODULE__{response: %Response{data: ""}} = state),
    do: {[], state}

  defp process_events(%__MODULE__{} = state) do
    {events, data} = Chunker.handle_chunk(state.response.data, state.chunker)
    {events, remaining} = Enum.split(state.events ++ events, state.demand)

    state = put_in(state.response.data, data)
    |> Map.put(:events, remaining)
    |> Map.put(:demand, state.demand - length(events))

    {events, state}
  end


  defp process_end(%__MODULE__{response: response} = state) do
    if response.status in 200..299 do
      {:stop, :normal, state}
    else
      {:stop, %HTTPError{status: state.response.status}, state}
    end
  end


  @impl true
  def terminate(reason, state) do
    Logger.debug("Terminating Terminus.Request: #{inspect reason}")
    HTTP.close(state.conn)
  end
  
end