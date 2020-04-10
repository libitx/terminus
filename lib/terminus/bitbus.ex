defmodule Terminus.Bitbus do
  @moduledoc """
  TODO
  """
  use Terminus.HTTPStream, host: "txo.bitbus.network"


  @doc """
  Crawls [Bitbus](https://bitbus.network) for blocks using the given query and
  streams the result.

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned. If a [`callback`](`t:Terminus.callback/0`)
  is provided, the stream is automatically run and the callback is called on
  each transaction.

  Optionally a linked GenStage [`pid`](`t:pid/0`) can be returned for using in
  combination with you own GenStage consumer.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token.
  * `host` - The Bitbus host. Defaults to `txo.bitbus.network`.
  * `linked_stage` - Return a linked GenStage [`pid`](`t:pid/0`) instead of a stream.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        q: %{find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }}
      }

  By default `Terminus.Bitbus.crawl/2` returns a streaming `t:Enumerable.t/0`.

      iex> Terminus.Bitbus.crawl(query, token: token)
      %Stream{}

  If a `t:Terminus.callback` is provided, the stream returns `:ok` and the
  callback is called on each transaction.

      iex> Terminus.Bitbus.crawl(query, [token: token], fn tx ->
      ...>   IO.inspect tx
      ...> end)
      :ok

  Optionally the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.Bitbus.crawl(query, token: token, linked_stage: true)
      #PID<>
  """
  @spec crawl(map | String.t, keyword, function) :: Enumerable.t | pid
  def crawl(query, options \\ [], ondata \\ nil)

  def crawl(%{} = query, opts, ondata),
    do: Jason.encode!(query) |> crawl(opts, ondata)

  def crawl(query, opts, ondata) when is_binary(query) do
    case stream("POST", "/block", query, opts) do
      {:ok, pid} when is_pid(pid) ->
        pid

      {:ok, stream} ->
        stream
        |> HTTPStream.parse_ndjson
        |> HTTPStream.handle_data(ondata)

      {:error, error} ->
        raise error
    end
  end


  @doc """
  Crawls [Bitbus](https://bitbus.network) for blocks using the given query and
  accumulates the result into a [`list`](`t:list/0`) of [`maps`](`t:map/0`).

  All requests must provide a valid [Planaria token](https://token.planaria.network).
  By default a streaming `t:Enumerable.t/0` is returned.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token.
  * `host` - The Bitbus host. Defaults to `txo.bitbus.network`.

  ## Examples

        iex> Terminus.Bitbus.crawl!(query, token: token)
        [%{}, ...]
  """
  @spec crawl!(map | String.t, keyword) :: list
  def crawl!(query, opts \\ []) do
    try do
      crawl(query, opts) |> Enum.to_list
    catch
      :exit, {error, _} ->
        raise error
    end
  end


  @doc """
  Fetches and returns the current status of [Bitbus](https://bitbus.network).

  The returned [`map`](`t:map/0`) of data includes the current block header as
  well as the total number of transactions in the block (`count`) .

  ## Examples

      iex> Terminus.Bitbus.status
      %{
        "hash" => "00000000000000000249f9bd0e127ebc62125a72686a7470fe4a41e4add2deb1",
        "prevHash" => "000000000000000001b3ea9c4c073226c6233583ab510ea10ce01faff17c89f3",
        "merkleRoot" => "fb19b1ff5cd838cfca399f9f2e46fa3a0e9f0da0459f91bfd6d02a75756f3a4d",
        "time" => 1586457301,
        "bits" => 402821143,
        "nonce" => 1471454449,
        "height" => 629967,
        "count" => 2193
      }
  
  """
  @spec status() :: map
  def status(opts \\ []) do
    case stream("GET", "/status", nil, opts) do
      {:ok, stream} ->
        stream
        |> Enum.to_list
        |> Enum.join
        |> Jason.decode!

      {:error, error} ->
        raise error
    end
  end
  
end