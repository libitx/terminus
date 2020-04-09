defmodule Terminus.HTTPStage do
  @moduledoc """
  TODO
  """
  use GenStage
  alias Mint.HTTP
  alias Terminus.Message
  alias Terminus.Response
  require Logger
  
  

  defstruct conn: nil,
            ref: nil,
            demand: 0,
            events: [],
            response: %Response{},
            last_resp: :init

  


  @doc """
  TODO
  """
  def connect(scheme, host, port) do
    GenStage.start_link(__MODULE__, {scheme, host, port})
  end


  @doc """
  TODO
  """
  def request(pid, method, path, headers, body) do
    GenStage.cast(pid, {:request, method, path, headers, body})
  end


  ## Callbacks

  @impl true
  def init({scheme, host, port}) do
    case Mint.HTTP.connect(scheme, host, port) do
      {:ok, conn} ->
        state = %__MODULE__{conn: conn}
        {:producer, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @impl true
  def handle_cast({:request, method, path, headers, body}, state) do
    case Mint.HTTP.request(state.conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = Map.merge(state, %{
          conn: conn,
          ref: request_ref
        })
        {:noreply, [], state}

      {:error, conn, reason} ->
        state = put_in(state.conn, conn)
        {:reply, {:error, reason}, state}
    end
  end


  @impl true
  def handle_demand(demand, state) do
    {remaining, events} = Enum.split(state.events, -1 * demand)
    state = Map.merge(state, %{
      demand: demand - length(events),
      events: remaining
    })
    {:noreply, Enum.reverse(events), state}
  end


  @impl true
  def handle_info(_message, %__MODULE__{last_resp: :done} = state) do
    {:stop, :normal, state}
  end

  def handle_info(message, state) do
    # TODO We should handle the error case here as well, but we're omitting it for brevity.
    case Mint.HTTP.stream(state.conn, message) do
      :unknown ->
        Logger.warn("Received unknown message: " <> inspect(message))
        {:noreply, [], state}

      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &process_response/2)
        {remaining, events} = Enum.split(state.events, -1 * state.demand)
        state = Map.merge(state, %{
          demand: state.demand - length(events),
          events: remaining
        })
        {:noreply, Enum.reverse(events), state}

      #{:error, conn, error} ->
      #  state = put_in(state.conn, conn)
      #  {:stop, error, state}
    end
  end


  # TODO
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
    put_filtered_event(state, data)
    |> Map.put(:last_resp, :data)
  end

  defp process_response({:done, request_ref}, %__MODULE__{ref: ref} = state)
    when request_ref == ref,
    do: put_in(state.last_resp, :done)

  defp put_filtered_event(state, ""), do: state
  defp put_filtered_event(state, data), do: update_in(state.events, &([data | &1]))


  @impl true
  def terminate(_reason, state) do
    Logger.debug("Terminating HTTPStream GenStage")
    Mint.HTTP.close(state.conn)
  end

end