defmodule Terminus.Bitsocket do
  @moduledoc """
  TODO
  """
  use Terminus.Streamer, host: "txo.bitsocket.network"


  @doc """
  Crawls the Bitsocket event database for transactions using the given query and
  returns a stream.

  Returns the result in an `:ok` / `:error` tuple pair.

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned.  Optionally a linked
  GenStage [`pid`](`t:pid/0`) can be returned for using in combination with your
  own GenStage consumer.

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream is
  automatically run and the callback is called on each transaction.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.
  * `stage` - Return a linked GenStage [`pid`](`t:pid/0`). Defaults to `false`.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }
      }

  By default `Terminus.Bitsocket.crawl/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitsocket.crawl(query, token: token)
      {:ok, %Stream{}}

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitsocket.crawl(query, token: token, stage: true)
      {:ok, #PID<>}

  If a [`callback`](`t:Terminus.callback/0`) is provided, the function
  returns `:ok` and the callback is called on each transaction.

      iex> Terminus.Bitsocket.crawl(query, [token: token], fn tx ->
      ...>   IO.inspect tx
      ...> end)
      :ok
  """
  @spec crawl(map | String.t, keyword, function) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, String.t}
  def crawl(query, options \\ [], ondata \\ nil)

  def crawl(query, options, nil) when is_function(options),
    do: crawl(query, [], options)

  def crawl(%{} = query, options, ondata),
    do: Jason.encode!(query) |> crawl(options, ondata)

  def crawl(query, options, ondata) when is_binary(query) do
    options = Keyword.put_new(options, :chunker, :ndjson)

    case stream("POST", "/crawl", query, options) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      {:ok, stream} ->
        handle_callback(stream, ondata)

      {:error, error} ->
        {:error, error}
    end
  end


  @doc """
  As `crawl/3` but returns the result or raises an exception if it fails.
  """
  @spec crawl!(map | String.t, keyword, function) :: Enumerable.t | pid | :ok
  def crawl!(query, options \\ [], ondata \\ nil) do
    case crawl(query, options, ondata) do
      :ok -> :ok

      {:ok, stream} ->
        stream

      {:error, error} ->
        raise error
    end
  end


  @doc """
  Crawls the Bitsocket event database for transactions using the given query and
  returns a stream.

  Returns the result in an `:ok` / `:error` tuple pair.

  This function is suitable for smaller limited queries as the entire result set
  is loaded in to memory an returned. For large crawls, `crawl/3` is preferred
  as the results can be streamed and processed more efficiently.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.

  ## Examples

        iex> Terminus.Bitsocket.fetch(query, token: token)
        [
          %{
            "tx" => %{"h" => "bbae7aa467cb34010c52033691f6688e00d9781b2d24620cab51827cd517afb8"},
            ...
          },
          ...
        ]
  """
  @spec fetch(map | String.t, keyword) :: {:ok, list} | {:error, String.t}
  def fetch(query, options \\ []) do
    options = Keyword.drop(options, [:stage])

    case crawl(query, options) do
      {:ok, stream} ->
        try do
          {:ok, Enum.to_list(stream)}
        catch
          :exit, {%HTTPError{} = error, _} ->
            {:error, HTTPError.message(error)}

          :exit, {error, _} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end


  @doc """
  As `fetch/2` but returns the result or raises an exception if it fails.
  """
  @spec fetch!(map | String.t, keyword) :: list
  def fetch!(query, options \\ []) do
    options = Keyword.drop(options, [:stage])
    case crawl(query, options) do
      {:ok, stream} ->
        try do
          Enum.to_list(stream)
        catch
          :exit, {error, _} ->
            raise error
        end

      {:error, error} ->
        raise error
    end
  end


  @doc """
  Subscribes to Bitsocket and streams realtime transaction events using the
  given query.

  Returns the result in an `:ok` / `:error` tuple pair.

  By default a streaming `t:Enumerable.t/0` is returned. Optionally a linked
  GenStage [`pid`](`t:pid/0`) can be returned for using in combination with your
  own GenStage consumer.

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream is
  automatically run and the callback is called on each transaction.

  As Bitsocket streams transactions using [Server Sent Events](https://en.wikipedia.org/wiki/Server-sent_events),
  the stream will stay open (and blocking) permanently. This is best managed
  inside a long-running Elixir process.  

  ## Options

  The accepted options are:

  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.
  * `stage` - Return a linked GenStage [`pid`](`t:pid/0`) instead of a stream.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }
      }

  By default `Terminus.Bitsocket.listen/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitsocket.listen(query, token: token)
      {:ok, %Stream{}}

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitsocket.listen(query, token: token, stage: true)
      {:ok, #PID<>}

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream returns `:ok`
  and the callback is called on each transaction.

      iex> Terminus.Bitsocket.listen(query, [token: token], fn tx ->
      ...>   IO.inspect tx
      ...> end)
      :ok
  """
  @spec listen(map | String.t, keyword, function) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, String.t}
  def listen(query, options \\ [], ondata \\ nil)

  def listen(query, options, nil) when is_function(options),
    do: listen(query, [], options)

  def listen(%{} = query, options, ondata),
    do: Jason.encode!(query) |> listen(options, ondata)

  def listen(query, options, ondata) when is_binary(query) do
    options = Keyword.put_new(options, :chunker, :eventsource)
    path = "/s/" <> Base.encode64(query)

    case stream("GET", path, nil, options) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      {:ok, stream} ->
        handle_callback(stream, ondata)

      {:error, error} ->
        {:error, error}
    end
  end


  @doc """
  As `listen/3` but returns the result or raises an exception if it fails.
  """
  @spec listen!(map | String.t, keyword) :: Enumerable.t | pid | :ok
  def listen!(query, options \\ []) do
    case listen(query, options) do
      :ok -> :ok

      {:ok, stream} ->
        stream

      {:error, error} ->
        raise error
    end
  end

end