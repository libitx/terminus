defmodule Terminus.EventSource do
  @moduledoc """
  TODO
  """
  use GenStage
  alias Mint.HTTP2, as: HTTP
  alias Terminus.Message
  require Logger


  # Defaults
  @headers [
    {"accept", "text/event-stream"},
    {"cache-control", "no-cache"}
  ]
  @restart_after 900_000


  defstruct conn: nil,
            ref: nil,
            url: nil,
            opts: [],
            ready_state: 0,
            response: %{status: nil, headers: []},
            last_event_id: nil,
            event_buf: "",
            events: [],
            demand: 0,
            #reconnect_time: 5000,
            restart_after: @restart_after,
            restart_timer: nil


  def test do
    path = %{q: %{find: %{"out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }}}
    |> Jason.encode!
    |> Base.encode64

    start("https://txo.bitsocket.network/s/" <> path)
  end

  
  @doc """
  TODO
  """
  def start(url, options \\ []) do
    GenStage.start(__MODULE__, {url, options})
  end


  @doc """
  TODO
  """
  def start_link(url, options \\ []) do
    GenStage.start_link(__MODULE__, {url, options})
  end


  @doc """
  TODO
  """
  def disconnect(pid) do
    GenStage.call(pid, :disconnect)
  end


  @doc """
  TODO
  """
  def reconnect(pid) do
    GenStage.call(pid, :reconnect)
  end


  # Callbacks
  

  @impl true
  def init({url, opts}) do
    %{scheme: scheme, host: host, port: port, path: path} = URI.parse(url)
    restart_after = Keyword.get(opts, :restart_after, @restart_after)

    with {:ok, conn} <- HTTP.connect(String.to_atom(scheme), host, port),
         {:ok, conn, request_ref} <- request(conn, path, opts)
    do
      restart_timer = Process.send_after(self(), :timeout_reconnect, restart_after)
      state = %__MODULE__{
        conn: conn,
        ref: request_ref,
        url: url,
        opts: opts,
        ready_state: 1,
        restart_after: restart_after,
        restart_timer: restart_timer
      }
      {:producer, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end


  # TODO
  defp request(conn, path, opts) do
    HTTP.request(conn, "GET", path, build_headers(opts), nil)
  end


  # TODO
  defp build_headers(opts) do
    conds = [
      {:last_event_id, & [{"last-event-id", &1} | &2]},
      {:token, & [{"token", &1} | &2]},
      {:headers, & &1 ++ &2}
    ]
    Enum.reduce(conds, @headers, fn {key, func}, headers ->
      case Keyword.get(opts, key) do
        nil -> headers
        value -> apply(func, [value, headers])
      end
    end)
  end


  @impl true
  def handle_call(:disconnect, _from, state) do
    case HTTP.cancel_request(state.conn, state.ref) do
      {:ok, conn} ->
        state = Map.merge(state, %{
          conn: conn,
          ready_state: 3
        })
        {:stop, {:shutdown, :disconnected}, state}

      {:error, reason} ->
        state = put_in(state.ready_state, 3)
        {:stop, {:error, reason}, state}
    end
  end


  @impl true
  def handle_call(:reconnect, _from, state) do
    opts = Keyword.put(state.opts, :last_event_id, state.last_event_id)
    %{path: path} = URI.parse(state.url)

    with {:ok, conn} <- HTTP.cancel_request(state.conn, state.ref),
         {:ok, conn, request_ref} <- request(conn, path, opts)
    do
      restart_timer = Process.send_after(self(), :timeout_reconnect, state.restart_after)
      state = Map.merge(state, %{
        conn: conn,
        ref: request_ref,
        ready_state: 1,
        restart_timer: restart_timer
      })
      {:reply, :ok, [], state}
    else
      {:error, reason} ->
        state = put_in(state.ready_state, 3)
        {:stop, {:error, reason}, state}
    end
  end


  @impl true
  def handle_demand(_demand, _state) do
    # TODO
  end


  #@impl true
  #def handle_info({:reconnect_time, time}, state) do
  #  state = put_in(state.reconnect_time, time)
  #  {:noreply, [], state}
  #end

  def handle_info(:timeout_reconnect, state) do
    IO.puts "FORCED RESTART"
    opts = Keyword.put(state.opts, :last_event_id, state.last_event_id)
    %{path: path} = URI.parse(state.url)

    with {:ok, conn} <- HTTP.cancel_request(state.conn, state.ref),
         {:ok, conn, request_ref} <- request(conn, path, opts)
    do
      restart_timer = Process.send_after(self(), :timeout_reconnect, state.restart_after)
      state = Map.merge(state, %{
        conn: conn,
        ref: request_ref,
        ready_state: 1,
        restart_timer: restart_timer
      })
      {:noreply, [], state}
    else
      {:error, reason} ->
        state = put_in(state.ready_state, 3)
        {:stop, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    case HTTP.stream(state.conn, message) do
      :unknown ->
        Logger.warn("Received unknown message: " <> inspect(message))
        {:noreply, [], state}

      {:ok, conn, responses} ->
        Process.cancel_timer(state.restart_timer)
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &process_response/2)
        events = state.events
        state = put_in(state.events, [])
        restart_timer = Process.send_after(self(), :timeout_reconnect, state.restart_after)
        state = put_in(state.restart_timer, restart_timer)
        {:noreply, events, state}

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
    when request_ref == ref,
    do: put_in(state.response.status, status)

  defp process_response({:headers, request_ref, headers}, %__MODULE__{ref: ref} = state)
    when request_ref == ref,
    do: update_in(state.response.headers, &(&1 ++ headers))

  defp process_response({:data, request_ref, data}, %__MODULE__{ref: ref} = state)
    when request_ref == ref,
    do: parse_data(data, state)

  defp process_response({:error, request_ref, reason}, %__MODULE__{ref: ref} = state)
    when request_ref == ref
  do
    Logger.error "Request error: #{ inspect reason }"
    put_in(state.ready_state, 2)
  end

  defp process_response({:done, request_ref}, %__MODULE__{ref: ref} = state)
    when request_ref == ref,
    do: put_in(state.ready_state, 2)
  
  
  # TODO
  defp parse_data(data, state) do
    buf = state.event_buf <> data
    {events, buf} = if String.ends_with?(buf, "\n") do
      events = buf
      |> String.split("\n")
      |> parse_eventsource_lines
      {events, ""}
    else
      {[], buf}
    end

    # Get the last event id
    last_event_id = case events do
      [%{id: last_event_id} | _] ->
        last_event_id
      _ ->
        state.last_event_id
    end
    
    # Reverse and parse into bitsocket events
    events = Enum.reverse(events)
    |> parse_bitsocket_data

    Map.merge(state, %{
      last_event_id: last_event_id,
      events: events,
      event_buf: buf
    })
  end

  
  # TODO
  defp parse_eventsource_lines(lines) when is_list(lines),
    do: parse_eventsource_lines(lines, [%Message{}])

  defp parse_eventsource_lines([""], messages),
    do: parse_eventsource_lines([], messages)

  defp parse_eventsource_lines(["" | lines], messages),
    do: parse_eventsource_lines(lines, [%Message{} | messages])

  defp parse_eventsource_lines([], messages),
   do: Enum.reject(messages, & &1.data == "")

  defp parse_eventsource_lines([line | lines], [msg | messages]) do
    msg = case line do
      ":" <> _ -> msg
      line ->
        String.split(line, ":", parts: 2)
        |> Enum.map(&String.trim/1)
        |> parse_eventsource_line(msg)
    end
    parse_eventsource_lines(lines, [msg | messages])
  end


  # TODO
  defp parse_eventsource_line([field, value], msg) do
    case field do
      "id" -> 
        put_in(msg.id, value)
      "event" ->
        put_in(msg.event, value)
      "data" ->
        update_in(msg.data, & &1 <> value <> "\n")
      "retry" ->
        #send(self(), {:reconnect_time, value})
        msg
      _ ->
        msg
    end
  end


  # TODO
  defp parse_bitsocket_data(events) do
    events
    |> Enum.map(& Jason.decode!(&1.data))
    |> Enum.filter(& &1["type"] == "push")
    |> Enum.flat_map(& &1["data"])
  end
  

  @impl true
  def terminate(reason, state) do
    Logger.debug("Terminating Terminus.Request: #{inspect reason}")
    HTTP.close(state.conn)
  end

end