defmodule Terminus.HTTPStream do
  @moduledoc """
  TODO
  """
  alias Terminus.HTTPStage
  alias Terminus.Message

  @headers [
    {"content-type", "application/json"}
  ]


  defmacro __using__(opts \\ []) do
    host = Keyword.get(opts, :host)

    quote do
      alias Terminus.HTTPStream
      defp stream(method, path, body, opts \\ []) do
        HTTPStream.init(method, unquote(host), path, body, opts)
      end
    end
  end


  @doc """
  TODO
  """
  def init(method, host, path, body, opts \\ []) do
    host    = Keyword.get(opts, :host, host)
    stage   = Keyword.get(opts, :stage, false)
    headers = case Keyword.get(opts, :token) do
      nil -> @headers
      token -> [{"token", token} | @headers]
    end
    
    with {:ok, pid} <- HTTPStage.connect(:https, host, 443),
         :ok <- HTTPStage.request(pid, method, path, headers, body)
    do
      if stage,
        do: {:ok, pid},
        else: {:ok, GenStage.stream([{pid, cancel: :transient}])}
    else
      error -> error
    end
  end


  @doc """
  TODO
  """
  def parse_ndjson(stream) do
    stream
    |> Stream.transform("", &transform_newline/2)
    |> Stream.reject(& is_nil(&1) || &1 == "")
    |> Stream.map(&Jason.decode!/1)
  end


  @doc """
  TODO
  """
  def parse_eventsource(stream) do
    stream
    |> Stream.transform("", &transform_eventsource/2)
    |> Stream.map(& Jason.decode!(&1.data))
    |> Stream.filter(& &1["type"] == "push")
    |> Stream.flat_map(& &1["data"])
  end


  @doc """
  TODO
  """
  def handle_data(stream, nil), do: stream
  def handle_data(stream, ondata) when is_function(ondata) do
    stream
    |> Stream.each(ondata)
    |> Stream.run
  end


  # TODO
  defp transform_newline(chunk, buffer) do
    data = buffer <> chunk
    |> String.split("\n")
    |> Enum.reverse

    case data do
      [tail] -> {[], tail}
      [tail | rest] ->
        if String.ends_with?(tail, "\n"),
          do: {Enum.reverse(data), ""},
          else: {Enum.reverse(rest), tail}
    end
  end


  defp transform_eventsource(chunk, buffer) do
    data = buffer <> chunk

    if String.ends_with?(data, "\n"),
      do: data |> String.split("\n") |> parse_messages([%Message{}]),
      else: {[], data}
  end


  defp parse_messages(["" | data], [msg | _] = messages) do
    case {data, msg.data} do
      {d, _} when d == [] or d == [""] ->
        parse_messages(data, messages)
      {_, ""} ->
        parse_messages(data, messages)
      _ ->
        parse_messages(data, [%Message{} | messages])
    end
  end

  defp parse_messages([], messages),
    do: {Enum.reverse(messages), ""}

  defp parse_messages([line | data], [msg | messages]) do
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

    parse_messages(data, [msg | messages])
  end

end