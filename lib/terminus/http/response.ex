defmodule Terminus.HTTP.Response do
  @moduledoc """
  TODO
  """
  alias Terminus.HTTP.SSEMessage, as: Message

  defstruct status: nil, headers: [], data: ""

  @type t :: %__MODULE__{
    status: integer,
    headers: list,
    data: binary
  }


  @doc """
  Decodes the data in the given response data buffer, using the specified decoder.
  """
  @spec decode_data(__MODULE__.t, [as: atom]) :: {__MODULE__.t, list}
  def decode_data(%__MODULE__{} = response, as: :raw) do
    events = [response.data]
    |> Enum.reject(& is_nil(&1) || &1 == "")

    response = put_in(response.data, "")
    {response, events}
  end

  def decode_data(%__MODULE__{} = response, as: :ndjson) do
    events = response.data
    |> String.split("\n")
    |> Enum.reject(& is_nil(&1) || &1 == "")

    {events, remaining} = if String.ends_with?(response.data, "\n") do
      {events, []}
    else
      Enum.split(events, -1)
    end

    response = put_in(response.data, Enum.join(remaining))
    events = Enum.map(events, &Jason.decode!/1)
    {response, events}
  end

  def decode_data(%__MODULE__{} = response, as: :eventsource) do
    events = response.data
    |> String.split("\n")
    |> Enum.reject(& is_nil(&1) || &1 == "")

    {events, remaining} = if String.ends_with?(response.data, "\n") do
      {events, []}
    else
      Enum.split(events, -1)
    end

    events = decode_eventsource_lines(events, [%Message{}])
    |> Enum.map(& Jason.decode!(&1.data))
    |> Enum.filter(& &1["type"] == "push")
    |> Enum.flat_map(& &1["data"])

    response = put_in(response.data, Enum.join(remaining))
    {response, events}
  end


  # Decodes eventsource line by line
  defp decode_eventsource_lines([""], messages),
    do: decode_eventsource_lines([], messages)

  defp decode_eventsource_lines(["" | lines], messages),
    do: decode_eventsource_lines(lines, [%Message{} | messages])

  defp decode_eventsource_lines([], messages),
   do: messages |> Enum.reject(& &1.data == "") |> Enum.reverse

  defp decode_eventsource_lines([line | lines], [msg | messages]) do
    msg = case line do
      ":" <> _ -> msg
      line ->
        String.split(line, ":", parts: 2)
        |> Enum.map(&String.trim/1)
        |> decode_eventsource_line(msg)
    end
    decode_eventsource_lines(lines, [msg | messages])
  end


  # Decodes eventsource line and puts into a SSE Message
  defp decode_eventsource_line([field, value], msg) do
    case field do
      "id" -> 
        put_in(msg.id, value)
      "event" ->
        put_in(msg.event, value)
      "data" ->
        update_in(msg.data, & &1 <> value <> "\n")
      #"retry" ->
      #  msg
      _ ->
        msg
    end
  end
  
end