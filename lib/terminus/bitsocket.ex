defmodule Terminus.Bitsocket do
  @moduledoc """
  Module for interfacing with the [Bitsocket](https://bitsocket.network) API.

  Bitsocket sends you realtime events from the Bitcoin blockchain. It uses
  [Server Sent Events](https://en.wikipedia.org/wiki/Server-sent_events) to
  stream new **unconfirmed** transactions as soon as they appear on the Bitcoin
  network.

  > Bitsocket is like Websocket, but for Bitcoin. With just a single Bitsocket
  > connection, you get access to a live, filterable stream of all transaction
  > events across the entire bitcoin peer network.

  ## Schema

  Realtime transactions have a similar schema to Bitbus documents. However, as
  these are unconfirmed transactions, they have no `blk` infomation and provide
  a `timestamp` attribute reflecting when Bitsocket first saw the transaction.

      %{
        "_id" => "...",       # Bitbus document ID
        "in" => [...],        # List of inputs
        "lock" => int,        # Lock time
        "out" => [...],       # List of outputs
        "timestamp" => int,   # Timestamp of when tx seen
        "tx" => %{
          "h" => "..."        # Transaction hash
        }
      }

  Bitsocket offers alternative endpoints for querying documents with inputs and
  outputs represented using either the [TXO schema](https://bitquery.planaria.network/#/?id=txo)
  OR the [BOB schema](https://bitquery.planaria.network/#/?id=bob). Terminus
  defaults to using the TXO endpoint, but the BOB endpoint can be used by
  specifying the `:host` option.

      Terminus.Bitsocket.listen(query, host: 'bob.bitsocket.network')

  ## Usage

  Subscribe to realtime Bitcoin transactions using `listen/3` and stream the
  results into your own data processing pipeline.

      iex> Terminus.Bitsocket.listen!(query)
      ...> |> Stream.map(&Terminus.BitFS.scan_tx/1)
      ...> |> Stream.each(&save_to_db/1)
      ...> |> Stream.run
      :ok

  Bitsocket also provides an API for querying and crawling the transaction event
  database which indexes all transactions in the previous 24 hours. Both `crawl/3`
  and `fetch/2` can be used to query these events.

      iex> Terminus.Bitsocket.fetch(%{
      ...>   find: %{
      ...>     "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn",
      ...>     "timestamp" => %{"$gt": :os.system_time(:millisecond) - 60000}
      ...>   },
      ...>   sort: %{ "timestamp": -1 }
      ...> }, token: token)
      {:ok, [
        %{
          "tx" => %{"h" => "fca7bdd7658613418c54872212811cf4c5b4f8ee16864eaf70cb1393fb0df6ca"},
          ...
        },
        ...
      ]}

  ### Endpoints

  Terminus supports both of the Bitsocket public enpoints. The endpoint can be
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
      txo: "https://txo.bitsocket.network",
      bob: "https://bob.bitsocket.network"
    ],
    headers: [
      {"cache-control", "no-cache"}
    ]


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
    |> Keyword.put(:headers, [{"content-type", "application/json"}])
    |> Keyword.put(:body, query)
    |> Keyword.put(:decoder, :ndjson)

    case request(:stream, "POST", "/crawl", options) do
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
  @spec fetch(Terminus.bitquery, keyword) ::
    {:ok, list} |
    {:error, Exception.t}
  def fetch(query, options \\ [])

  def fetch(%{} = query, options),
    do: query |> normalize_query |> Jason.encode! |> fetch(options)

  def fetch(query, options) do
    options = Keyword.take(options, [:token, :host])
    |> Keyword.put(:headers, [{"content-type", "application/json"}])
    |> Keyword.put(:body, query)
    |> Keyword.put(:decoder, :ndjson)

    request(:fetch, "POST", "/crawl", options)
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
  * `recycle` - Number of seconds after which to recycle to a quiet Bitsocket request. Defaults to `900`.

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
  @spec listen(Terminus.bitquery, keyword, Terminus.callback) ::
    {:ok, Enumerable.t | pid} | :ok |
    {:error, Exception.t}
  def listen(query, options \\ [], ondata \\ nil)

  def listen(query, options, nil) when is_function(options),
    do: listen(query, [], options)

  def listen(%{} = query, options, ondata),
    do: query |> normalize_query |> Jason.encode! |> listen(options, ondata)

  def listen(query, options, ondata) when is_binary(query) do
    path = "/s/" <> Base.encode64(query)
    recycle_after = Keyword.get(options, :recycle, 900)
    options = options
    |> Keyword.take([:token, :host, :stage])
    |> Keyword.put(:headers, [{"accept", "text/event-stream"}])
    |> Keyword.put(:decoder, :eventsource)
    |> Keyword.put(:recycle_after, recycle_after)

    case request(:stream, "GET", path, options) do
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
  @spec listen!(Terminus.bitquery, keyword) :: Enumerable.t | pid | :ok
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