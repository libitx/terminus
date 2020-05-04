defmodule Terminus.Bitbus do
  @moduledoc """
  Module for interfacing with the [Bitbus](https://bitbus.network) API.

  Bitbus is a powerful API that allows you to crawl a filtered subset of the
  Bitcoin blockchain. Bitbus indexes blocks, thus can be used to crawl
  **confirmed** transactions.

  > We run a highly efficient bitcoin crawler which indexes the bitcoin
  > blockchain. Then we expose the index as an API so anyone can easily crawl
  > ONLY the subset of bitcoin by crawling bitbus.

  ## Schema

  Bitbus transaction documents have the following schema:

      %{
        "_id" => "...",       # Bitbus document ID
        "blk" => %{
          "h" => "...",       # Block hash
          "i" => int,         # Block height
          "t" => int,         # Block timestamp
        },
        "in" => [...],        # List of inputs
        "lock" => int,        # Lock time
        "out" => [...],       # List of outputs
        "tx" => %{
          "h" => "..."        # Transaction hash
        }
      }

  Transactions inputs and outputs are represented using the [TXO schema](https://bitquery.planaria.network/#/?id=txo).

  ## Usage

  For smaller queries of limited results, `fetch/2` can be used to return a list
  of transactions:

      iex> Terminus.Bitbus.fetch(%{
      ...>   find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" },
      ...>   sort: %{ "blk.i": -1 },
      ...>   limit: 5
      ...> }, token: token)
      {:ok, [
        %{
          "tx" => %{"h" => "fca7bdd7658613418c54872212811cf4c5b4f8ee16864eaf70cb1393fb0df6ca"},
          ...
        },
        ...
      ]}

  For larger crawl operations, use `crawl/3` to stream results into your own
  data processing pipeline.

      iex> Terminus.Bitbus.crawl!(query, token: token)
      ...> |> Stream.map(&Terminus.BitFS.scan_tx/1)
      ...> |> Stream.each(&save_to_db/1)
      ...> |> Stream.run
      :ok
  
  ### Endpoints

  Terminus supports both of the Bitbus public enpoints. The endpoint can be
  selected by passing the `:host` option to any API method.
  
  The available endpoints are:

  * `:txo` - Query and return transactions in the Transaction Object schema. Default.
  * `:bob` - Query and return transactions in the Bitcoin OP_RETURN Bytecode schema.

      # By default the TXO endpoint is used
      iex> Terminus.crawl(query, token: token)

      # Optionally use the BOB endpoint
      iex> Terminus.crawl(query, host: :bob, token: token)
  """
  use Terminus.HTTPStream,
    hosts: [
      txo: "https://txo.bitbus.network",
      bob: "https://bob.bitbus.network"
    ],
    headers: [
      {"cache-control", "no-cache"},
      {"content-type", "application/json"}
    ]


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
  * `host` - The Bitbus host. Defaults to "https://txo.bitbus.network".
  * `stage` - Return a linked GenStage [`pid`](`t:pid/0`). Defaults to `false`.

  ## Examples

  Queries should be in the form of any valid [Bitquery](https://bitquery.planaria.network/).

      query = %{
        find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" }
      }

  By default `Terminus.Bitbus.crawl/3` returns a streaming `t:Enumerable.t/0`.

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
  @spec crawl(Terminus.bitquery, keyword, Terminus.callback) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, Exception.t}
  def crawl(query, options \\ [], ondata \\ nil)

  def crawl(query, options, nil) when is_function(options),
    do: crawl(query, [], options)

  def crawl(%{} = query, options, ondata),
    do: query |> normalize_query |> Jason.encode! |> crawl(options, ondata)

  def crawl(query, options, ondata) when is_binary(query) do
    options = options
    |> Keyword.take([:token, :host, :stage])
    |> Keyword.put(:body, query)
    |> Keyword.put(:decoder, :ndjson)

    case request(:stream, "POST", "/block", options) do
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
  @spec crawl!(Terminus.bitquery, keyword, Terminus.callback) ::
    Enumerable.t | pid | :ok
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
  * `host` - The Bitbus host. Defaults to "https://txo.bitbus.network".

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
  @spec fetch(Terminus.bitquery, keyword) ::
    {:ok, list} |
    {:error, Exception.t}
  def fetch(query, options \\ [])

  def fetch(%{} = query, options),
    do: query |> normalize_query |> Jason.encode! |> fetch(options)

  def fetch(query, options) when is_binary(query) do
    options = Keyword.take(options, [:token, :host])
    |> Keyword.put(:body, query)
    |> Keyword.put(:decoder, :ndjson)

    request(:fetch, "POST", "/block", options)
  end


  @doc """
  As `fetch/2` but returns the result or raises an exception if it fails.
  """
  @spec fetch!(Terminus.bitquery, keyword) :: list
  def fetch!(query, options \\ []) do    
    case fetch(query, options) do
      {:ok, data} ->
        data

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
  @spec status(keyword) :: {:ok, map} | {:error, Exception.t}
  def status(options \\ []) do
    options = Keyword.take(options, [:host])

    case request(:fetch, "GET", "/status", options) do
      {:ok, body} ->
        Jason.decode(body)

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