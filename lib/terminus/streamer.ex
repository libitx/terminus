defmodule Terminus.Streamer do
  @moduledoc """
  A mixin module providing functions for creating streaming HTTP requests.

  ## Examples

      defmodule BitFS do
        use Terminus.Streamer, host: "x.bitfs.network"

        def load_file(path) do
          case stream("GET", path, nil) do
            {:ok, stream} ->
              stream |> Enum.to_list |> Enum.join
            {:error, reason} ->
              raise reason
          end
        end
      end
  
  """
  alias Terminus.{HTTPError,Request}

  @typedoc "On-data callback function."
  @type callback :: function | nil


  @scheme Application.get_env(:terminus, :scheme)
  @port Application.get_env(:terminus, :port)
  @headers [
    {"content-type", "application/json"}
  ]


  @doc false
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
  Opens a HTTP connection and begins a request, returning the GenStage [`pid`](`t:pid/0`)
  of the request.

  Returns the result in an `:ok` / `:error` tuple pair.
  """
  @spec request(String.t, String.t, String.t, String.t | nil, keyword) ::
    {:ok, pid} |
    {:error, String.t}
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
  Opens a HTTP connection and begins a request, returning a streaming `t:Enumerable.t/0`.

  Returns the result in an `:ok` / `:error` tuple pair.
  """
  @spec stream(String.t, String.t, String.t, String.t | nil, keyword) ::
    {:ok, Enumerable.t | pid} |
    {:error, String.t}
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
  Runs the given streaming `t:Enumerable.t/0` and executes the [`callback`](`t:callback/0`)
  on each element of the stream.

  If the given callback is `nil` then the stream is passed through and returned.
  """
  @spec handle_callback(Enumerable.t, callback) ::
    {:ok, Enumerable.t} | :ok |
    {:error, String.t}
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
  Normalizes the given Bitquery, automatically expanding shorthand queries.

  ## Examples

      iex> normalize_query(%{find: %{"tx.h" => "abc"}})
      %{
        v: 3,
        q: %{
          find: %{
            "tx.h" => "abc"
          }
        }
      }
  """
  @spec normalize_query(map) :: map
  def normalize_query(%{find: _} = query),
    do: %{v: 3, q: query}

  def normalize_query(%{"find" => _} = query),
    do: %{v: 3, q: query}

  def normalize_query(%{} = query), do: query


  # Returns the default headers with a token header if the token is given.
  defp build_headers(nil), do: @headers
  defp build_headers(token),
    do: [{"token", token} | @headers]

end