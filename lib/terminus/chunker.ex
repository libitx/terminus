defmodule Terminus.Chunker do
  @moduledoc """
  TODO
  """
  alias Terminus.Message
  
  @doc """
  TODO
  """
  def handle_chunk(nil, data), do: handle_chunk(:raw, data)
  def handle_chunk(:raw, data), do: {[data], ""}

  def handle_chunk(:ndjson, data) do
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

  def handle_chunk(:eventsource, data) do
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


  # TODO
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