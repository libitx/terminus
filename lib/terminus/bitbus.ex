defmodule Terminus.Bitbus do
  @moduledoc """
  TODO
  """
  use Terminus.Streamer, host: "txo.bitbus.network"


  @doc """
  Crawls Bitbus for transactions using the given query and returns a stream.

  Returns the result in an `:ok` / `:error` tuple pair.

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned. Optionally a linked
  GenStage [`pid`](`t:pid/0`) can be returned for using in combination with your
  own GenStage consumer.

  If a [`callback`](`t:Terminus.callback/0`) is provided, the stream is
  automatically run and the callback is called on each transaction.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitbus host. Defaults to `txo.bitbus.network`.
  * `stage` - Return a linked GenStage [`pid`](`t:pid/0`). Defaults to `false`.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }
      }

  By default `Terminus.Bitbus.crawl/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitbus.crawl(query, token: token)
      {:ok, %Stream{}}

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitbus.crawl(query, token: token, stage: true)
      {:ok, #PID<>}

  If a [`callback`](`t:Terminus.callback/0`) is provided, the function
  returns `:ok` and the callback is called on each transaction.

      iex> Terminus.Bitbus.crawl(query, [token: token], fn tx ->
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

    case stream("POST", "/block", query, options) do
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
  Crawls Bitbus for transactions using the given query and returns a list of
  transactions.

  Returns the result in an `:ok` / `:error` tuple pair.

  This function is suitable for smaller limited queries as the entire result set
  is loaded in to memory an returned. For large crawls, `crawl/3` is preferred
  as the results can be streamed and processed more efficiently.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitbus host. Defaults to `txo.bitbus.network`.

  ## Examples

        iex> Terminus.Bitbus.fetch(query, token: token)
        {:ok, [
          %{
            "tx" => %{"h" => "bbae7aa467cb34010c52033691f6688e00d9781b2d24620cab51827cd517afb8"},
            ...
          },
          ...
        ]}
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
  Fetches and returns the current status of Bitbus.

  Returns the result in an `:ok` / `:error` tuple pair. The returned [`map`](`t:map/0`)
  of data includes the current block header as well as the total number of
  transactions in the block (`count`).

  ## Examples

      iex> Terminus.Bitbus.status
      {:ok, %{
        "hash" => "00000000000000000249f9bd0e127ebc62125a72686a7470fe4a41e4add2deb1",
        "prevHash" => "000000000000000001b3ea9c4c073226c6233583ab510ea10ce01faff17c89f3",
        "merkleRoot" => "fb19b1ff5cd838cfca399f9f2e46fa3a0e9f0da0459f91bfd6d02a75756f3a4d",
        "time" => 1586457301,
        "bits" => 402821143,
        "nonce" => 1471454449,
        "height" => 629967,
        "count" => 2193
      }}
  """
  @spec status(keyword) :: {:ok, map} | {:error, String.t}
  def status(options \\ []) do
    options = Keyword.take(options, [:host])

    case stream("GET", "/status", nil, options) do
      {:ok, stream} ->
        stream
        |> Enum.to_list
        |> Enum.join
        |> Jason.decode

      {:error, error} ->
        {:error, error}
    end
  end


  @doc """
  As `status/1` but returns the result or raises an exception if it fails.
  """
  @spec status!(keyword) :: map
  def status!(options \\ []) do
    case status(options) do
      {:ok, data} ->
        data

      {:error, error} ->
        raise error
    end
  end
  
end