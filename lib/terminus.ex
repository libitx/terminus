defmodule Terminus do
  @moduledoc """
  Terminus allows you to crawl and subscribe to Bitcoin transaction events using
  [Bitbus](https://bitbus.network) and [Bitsocket](https://bitsocket.network),
  and download binary data from [BitFS](https://bitfs.network).

  > **terminus** &mdash; noun
  > * the end of a railway or other transport route, or a station at such a point; a terminal.
  > * a final point in space or time; an end or extremity.

  Terminus provides a single unified interface for crawling and querying Bitbus,
  Bitsocket and BitFS in a highly performant manner. Each request is a `GenStage`
  process, enabling you to create powerful concurrent data flows. Terminus may
  well be the most powerful way of querying Bitcoin in the Universe!

  ## Apis

  Terminus can be used to interface with the following Planaria Corp APIs.

  * [`Bitbus`](`Terminus.Bitbus`) - crawl filtered subsets of **confirmed** Bitcoin transactions in blocks.
  * [`Bitsocket`](`Terminus.Bitsocket`) - subscribe to a live, filterable stream of realtime transaction events.
  * [`BitFS`](`Terminus.BitFS`) - fetch raw binary data chunks (over 512kb) indexed from all Bitcoin transactions.

  ### Authentication

  Both Bitbus and Bitsocket require a token to authenticate requests. *(The Bitsocket
  `listen` API currently doesn't require a token but that is likely to change).*
  Currently tokens are free with no usage limits. *(Also likely to change)*

  **[Get your Planaria Token](https://token.planaria.network).**

  ### Query language

  Both Bitbus and Bitsocket use the same MongoDB-like query language, known as
  [Bitquery](https://bitquery.planaria.network). Terminus allows the optional
  use of shorthand queries (just the `q` value).

      iex> Terminus.Bitbus.fetch!(%{
      ...>   find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" },
      ...>   sort: %{ "blk.i": -1 },
      ...>   project: %{ "tx.h": 1 },
      ...>   limit: 5
      ...> }, token: token)
      [
        %{"tx" => %{"h" => "fca7bdd7658613418c54872212811cf4c5b4f8ee16864eaf70cb1393fb0df6ca"}},
        %{"tx" => %{"h" => "79ae3ca23d1067b9ab45aba7e8ff4de1943e383e9a33e562d5ffd8489f388c93"}},
        %{"tx" => %{"h" => "5526989417f28da5e0c99b58863db58c1faf8862ac9325dc415ad4b11605c1b1"}},
        %{"tx" => %{"h" => "0bac587681360f961dbccba4c49a5c8f1b6f0bef61fe8501a28dcfe981a920b5"}},
        %{"tx" => %{"h" => "fa13a8f0f5688f761b2f34949bb35fa5d6fd14cb3d49c2c1617363b6984df162"}}
      ]

  ## Using Terminus
  
  Terminus can be used as a simple client for crawling and querying Bitbus and
  Bitsocket APIs, and fetching binary data from BitFS. For simple examples,
  refer to the `Terminus.Bitbus`, `Terminus.Bitsocket` and `Terminus.BitFS`
  documentation.

  ### Streams
  
  Most Terminus functions return a streaming `t:Enumerable.t/0` allowing you to
  compose data processing pipelines and operations.

      iex> Terminus.Bitbus.crawl!(query, token: token)
      ...> |> Stream.map(&Terminus.BitFS.scan_tx/1)
      ...> |> Stream.each(&save_to_db/1)
      ...> |> Stream.run
      :ok
  
  ### Planaria

  Using `Terminus.Planaria` inside a module allows you to simply recreate
  [Planaria](https://neon.planaria.network)-like state machine functionality.

  Planarias can be started under your app's supervision tree, allowing multiple
  Planaria processes to run concurrently.

      defmodule TwetchScraper do
        @query %{
          "find" => %{
            "out.s2": "19HxigV4QyBv3tHpQVcUEQyq1pzZVdoAut",
            "out.s25": "twetch"
          }
        }

        use Terminus.Planaria, token: Application.get_env(:my_app, :token),
                               from: 600000,
                               query: @query

        def handle_data(:block, txns) do
          # Handle confirmed transactions
        end

        def handle_data(:mempool, txns) do
          # Handle unconfirmed transactions
        end
      end

  ### Concurrency

  Under the hood, each Terminus request is a `GenStage` producer process, and
  the bare [`pid`](`t:pid/0`) can be returned. This allows you to take full
  advantage of Elixir's concurrency, by either using with your own `GenStage`
  consumers or using a tool like `Flow` to create powerful concurrent pipelines.

      # One stream of transactions will be distributed across eight concurrent
      # processes for mapping and saving the data.
      iex> {:ok, pid} = Terminus.Bitbus.crawl(query, token: token, stage: true)
      iex> Flow.from_stages([pid], stages: 8)
      ...> |> Flow.map(&Terminus.BitFS.scan_tx/1)
      ...> |> Flow.map(&save_to_db/1)
      ...> |> Flow.run
      :ok
  """

  @typedoc "Bitcoin data query language."
  @type bitquery :: map | String.t

  @typedoc "BitFS URI scheme."
  @type bitfs_uri :: String.t

  @typedoc "On-data callback function."
  @type callback :: function

  @typedoc "Hex-encoded transaction ID."
  @type txid :: function

end
