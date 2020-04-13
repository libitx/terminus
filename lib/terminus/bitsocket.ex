defmodule Terminus.Bitsocket do
  @moduledoc """
  TODO
  """
  use Terminus.Streamer, host: "txo.bitsocket.network"


  @doc """
  Crawls the [Bitsocket](https://bitsocket.network) event database for
  transactions using the given query and streams the result.

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned. If a [`callback`](`t:Terminus.callback/0`)
  is provided, the stream is automatically run and the callback is called on
  each transaction.

  Optionally a linked GenStage [`pid`](`t:pid/0`) can be returned for using in
  combination with you own GenStage consumer.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token.
  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.
  * `linked_stage` - Return a linked GenStage [`pid`](`t:pid/0`) instead of a stream.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        q: %{find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }}
      }

  By default `Terminus.Bitsocket.crawl/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitsocket.crawl(query, token: token)
      %Stream{}

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream returns `:ok`
  and the callback is called on each transaction.

      iex> Terminus.Bitsocket.crawl(query, [token: token], fn tx ->
      ...>   IO.inspect tx
      ...> end)
      :ok

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitsocket.crawl(query, token: token, linked_stage: true)
      #PID<>
  """
  @spec crawl(map | String.t, keyword, function) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, String.t}
  def crawl(query, options \\ [], ondata \\ nil)

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
  Crawls the [Bitsocket](https://bitsocket.network) event database for
  transactions using the given query and accumulates the result into a
  [`list`](`t:list/0`) of [`maps`](`t:map/0`).

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token.
  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.

  ## Examples

        iex> Terminus.Bitsocket.crawl!(query, token: token)
        [%{
          "tx" => %{"h" => "741bcaf3f5ec40a48d78fcc0314ce260547122e8f69c51cedbf9e56ec3388c35"},
          ...
        }, ...]
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
  TODO
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
  TODO
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
  Subscribe to [Bitsocket](https://bitsocket.network) events to stream realtime
  transactions using the given query.

  By default a streaming `t:Enumerable.t/0` is returned. If a [`callback`](`t:Terminus.callback/0`)
  is provided, the stream is automatically run and the callback is called on
  each transaction.

  As Bitsocket streams transactions using [Server Sent Events](https://en.wikipedia.org/wiki/Server-sent_events),
  the stream will stay open (and blocking) permanently. This is best managed
  inside a long-running Elixir process.

  Optionally a linked GenStage [`pid`](`t:pid/0`) can be returned for using in
  combination with you own GenStage consumer.

  ## Options

  The accepted options are:

  * `host` - The Bitsocket host. Defaults to `txo.bitsocket.network`.
  * `linked_stage` - Return a linked GenStage [`pid`](`t:pid/0`) instead of a stream.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        q: %{find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }}
      }

  By default `Terminus.Bitsocket.listen/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitsocket.listen(query, token: token)
      %Stream{}

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream returns `:ok`
  and the callback is called on each transaction.

      iex> Terminus.Bitsocket.listen(query, [token: token], fn tx ->
      ...>   IO.inspect tx
      ...> end)
      :ok

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitsocket.listen(query, token: token, linked_stage: true)
      #PID<>
  """
  @spec listen(map | String.t, keyword, function) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, String.t}
  def listen(query), do: listen(query, [], nil)

  def listen(query, options) when is_list(options),
    do: listen(query, options, nil)

  def listen(query, ondata) when is_function(ondata),
    do: listen(query, [], ondata)

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
  TODO
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