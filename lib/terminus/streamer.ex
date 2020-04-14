defmodule Terminus.Streamer do
  @moduledoc """
  TODO
  """
  alias Terminus.{HTTPError,Request}

  @scheme Application.get_env(:terminus, :scheme)
  @port Application.get_env(:terminus, :port)
  @headers [
    {"content-type", "application/json"}
  ]


  defmacro __using__(opts \\ []) do
    host = Keyword.get(opts, :host)

    quote do
      alias Terminus.{Chunker, HTTPError, Streamer}

      @doc false
      def stream(method, path, body, opts \\ []),
        do: Streamer.stream(method, unquote(host), path, body, opts)

      @doc false
      def handle_callback(stream, ondata),
        do: Streamer.handle_callback(stream, ondata)

      @doc false
      def normalize_query(query),
        do: Streamer.normalize_query(query)

      
    end
  end


  @doc """
  TODO
  """
  def request(method, host, path, body, opts \\ []) do
    host    = Keyword.get(opts, :host, host)
    token   = Keyword.get(opts, :token)
    headers = build_headers(token)
    chunker = Keyword.get(opts, :chunker)

    with {:ok, pid} <- Request.connect(@scheme, host, @port, opts),
         :ok <- Request.request(pid, method, path, headers, body, chunker)
    do
      {:ok, pid}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end


  @doc """
  TODO
  """
  def stream(method, host, path, body, opts \\ []) do
    stage = Keyword.get(opts, :stage, false)

    case request(method, host, path, body, opts) do
      {:ok, pid} ->
        if stage,
          do: {:ok, pid},
          else: {:ok, GenStage.stream([{pid, cancel: :transient}])}
      {:error, reason} ->
        {:error, reason}
    end
  end


  @doc """
  TODO
  """
  def handle_callback(stream, nil), do: {:ok, stream}
  def handle_callback(stream, ondata) when is_function(ondata) do
    try do
      stream
      |> Stream.each(ondata)
      |> Stream.run
    catch
      :exit, {%HTTPError{} = error, _} ->
        {:error, HTTPError.message(error)}

      :exit, {error, _} ->
        {:error, error}
    end
  end


  @doc """
  TODO
  """
  def normalize_query(%{find: _} = query),
    do: %{v: 3, q: query}

  def normalize_query(%{"find" => _} = query),
    do: %{v: 3, q: query}

  def normalize_query(%{} = query), do: query


  # TODO
  defp build_headers(nil), do: @headers
  defp build_headers(token),
    do: [{"token", token} | @headers]

end