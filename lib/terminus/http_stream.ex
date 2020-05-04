defmodule Terminus.HTTPStream do
  @moduledoc """
  A mixin module providing functions for creating streaming HTTP requests.

  ## Examples

      defmodule BitFS do
        use Terminus.HTTPStream, hosts: ["x.bitfs.network"]

        def load_file(path) do
          case request(:fetch, "GET", path, nil) do
            {:ok, data} ->
              data
            {:error, reason} ->
              raise reason
          end
        end

        def stream_file(path) do
          case request(:stream, "GET", path, nil) do
            {:ok, stream} ->
              stream
            {:error, reason} ->
              raise reason
          end
        end
      end
  
  """
  alias Terminus.HTTP


  @doc false
  defmacro __using__(opts \\ []) do
    hosts = Keyword.get(opts, :hosts)
    headers = Keyword.get(opts, :headers, [])

    quote location: :keep do
      alias Terminus.{HTTP,HTTPStream}

      @doc false
      def request(func, method, path, opts \\ []) do
        host = get_host(opts)
        opts = Keyword.put_new(opts, :headers, [])
        |> Keyword.update!(:headers, & unquote(headers) ++ &1)

        try do
          apply(HTTPStream, func, [method, host, path, opts])
        catch    
          :exit, {error, _} ->
            {:error, error}
        end
      end

      @doc false
      def handle_callback(stream, ondata),
        do: HTTPStream.handle_callback(stream, ondata)

      @doc false
      def normalize_query(query),
        do: HTTPStream.normalize_query(query)
      
      # Gets the host from atom or given binary string
      defp get_host(opts) do
        case Keyword.get(opts, :host) do
          nil ->
            unquote(hosts) |> List.first |> elem(1)
          key when is_atom(key) ->
            unquote(hosts) |> Keyword.get(key)
          url when is_binary(url) ->
            url
        end
      end

    end
  end


  @doc """
  Opens a HTTP connection and begins a request, returning the GenStage [`pid`](`t:pid/0`)
  of the request.

  Returns the result in an `:ok` / `:error` tuple pair.
  """
  @spec request(String.t, String.t, String.t, keyword) ::
  {:ok, Enumerable.t | pid} |
    {:error, String.t}
  def request(method, host, path, options \\ []) do
    with {:ok, pid} <- HTTP.Client.connect(host, options),
         :ok <- HTTP.Client.request(pid, method, path, options)
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
  @spec stream(String.t, String.t, String.t, keyword) ::
    {:ok, Enumerable.t | pid} |
    {:error, String.t}
  def stream(method, host, path, options \\ []) do
    stage? = Keyword.get(options, :stage, false)

    case request(method, host, path, options) do
      {:ok, pid} ->
        if stage?,
          do: {:ok, pid},
          else: {:ok, GenStage.stream([{pid, cancel: :transient}])}

      {:error, reason} ->
        {:error, reason}
    end
  end


  @doc """
  Opens a HTTP connection and begins a request, returning the `t:binary/0` body
  of the response.

  Returns the result in an `:ok` / `:error` tuple pair.
  """
  @spec fetch(String.t, String.t, String.t, keyword) ::
    {:ok, Enumerable.t | pid} |
    {:error, String.t}
  def fetch(method, host, path, options \\ []) do
    raw? = Keyword.get(options, :decoder, :raw) == :raw
    
    case stream(method, host, path, options) do
      {:ok, stream} ->
        list = Enum.to_list(stream)
        if raw?,
          do: {:ok, Enum.join(list)},
          else: {:ok, list}

      {:error, reason} ->
        {:error, reason}
    end
  end


  @doc """
  Runs the given streaming `t:Enumerable.t/0` and executes the [`callback`](`t:Terminus.callback/0`)
  on each element of the stream.

  If the given callback is `nil` then the stream is passed through and returned.
  """
  @spec handle_callback(Enumerable.t, Terminus.Streamer.callback) ::
    {:ok, Enumerable.t} | :ok |
    {:error, String.t}
  def handle_callback(stream, nil), do: {:ok, stream}
  def handle_callback(stream, ondata) when is_function(ondata) do
    try do
      stream
      |> Stream.each(ondata)
      |> Stream.run
    catch
      :exit, {%HTTP.Error{} = error, _} ->
        {:error, HTTP.Error.message(error)}

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
    do: normalize_query(%{"q" => query})

  def normalize_query(%{"find" => _} = query),
    do: normalize_query(%{"q" => query})

  def normalize_query(%{"q" => _} = query),
    do: stringify_keys(query)


  # Convert map atom keys to strings
  defp stringify_keys(%{} = map) do
    map
    |> Enum.map(&stringify_keys/1)
    |> Enum.into(%{})
  end

  defp stringify_keys({k, v}) when is_atom(k),
    do: {Atom.to_string(k), stringify_keys(v)}
  
  defp stringify_keys({k, v}) when is_binary(k),
    do: {k, stringify_keys(v)}

  defp stringify_keys([head | rest]),
     do: [stringify_keys(head) | stringify_keys(rest)]

  defp stringify_keys(val), do: val

end