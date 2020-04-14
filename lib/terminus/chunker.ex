defmodule Terminus.Chunker do
  @moduledoc """
  Module for reducing data chunks from streaming HTTP requests into structured
  data messages.
  """
  defmodule Message do
    @moduledoc false
    defstruct id: nil, event: "message", data: ""
  end

  
  @doc """
  Handles the conversion of the given binary data chunk into a list of one or
  more structured types.

  Returns a tuple containing a list of events and a binary of any remaining data.

  ## Examples

      iex> "{\"foo\":\"bar\"}\n{\"foo\":\"bar\"}\n{\"fo"
      ...> |> Terminus.Chunker.handle_chunk(:ndjson)
      {[%{"foo" => "bar"}, %{"foo" => "bar"}], "{\"fo"}
  """
  @spec handle_chunk(binary, atom) :: {list, binary}
  def handle_chunk(data, nil), do: handle_chunk(data, :raw)
  def handle_chunk(data, :raw), do: {[data], ""}

  def handle_chunk(data, :ndjson) do
    events = data
    |> String.split("\n")
    |> Enum.reject(& is_nil(&1) || &1 == "")

    {events, data} = if String.ends_with?(data, "\n") do
      {events, []}
    else
      Enum.split(events, -1)
    end

    events = Enum.map(events, &Jason.decode!/1)
    data = Enum.join(data)

    {events, data}
  end

  def handle_chunk(data, :eventsource) do
    {events, data} = if String.ends_with?(data, "\n") do
      events = data
      |> String.split("\n")
      |> parse_sse_messages([%Message{}])
      {events, ""}
    else
      {[], data}
    end

    events = events
    |> Enum.map(& Jason.decode!(&1.data))
    |> Enum.filter(& &1["type"] == "push")
    |> Enum.flat_map(& &1["data"])

    {events, data}
  end


  # Parses a SSE Messages from the list of strings
  defp parse_sse_messages(["" | []], messages),
    do: parse_sse_messages([], messages)

  defp parse_sse_messages(["" | lines], [%Message{data: ""} | _] = messages),
    do: parse_sse_messages(lines, messages)

  defp parse_sse_messages(["" | lines], messages),
    do: parse_sse_messages(lines, [%Message{} | messages])

  defp parse_sse_messages([], messages) do
    messages
    |> Enum.reject(& &1.data == "")
    |> Enum.reverse
  end

  defp parse_sse_messages([line | lines], [msg | messages]) do
    msg = case line do
      ":" <> _ -> msg
      line ->
        [field, value] = line
        |> String.split(":", parts: 2)
        |> Enum.map(&String.trim/1)

        case field do
          "id" -> Map.put(msg, :id, value)
          "event" -> Map.put(msg, :event, value)
          "data" ->
            Map.put(msg, :data, msg.data <> value <> "\n")
          _ -> msg
        end
    end

    parse_sse_messages(lines, [msg | messages])
  end
  
end