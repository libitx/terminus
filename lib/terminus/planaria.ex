defmodule Terminus.Planaria do
  @moduledoc """
  A behaviour module for implementing [Planaria](https://neon.planaria.network)-like
  state machines in Elixir.

  A module using `Terminus.Planaria` is a GenStage consumer process that will
  automatically mangage its own producer processes to crawl and listen to Bitcoin
  transaction events. Developers only need to implement callback functions to
  handle transaction events.

  ## Example

  The following code demonstrates how a [Twetch](http://twetch.app) scraper can
  be built in a few lines of code.

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

  The `c:handle_data/2` callback can be implemented for each [`tx_event`](`t:tx_event/0`),
  and is typically be used to persist required data from each transaction. The
  `c:handle_tape/2` callback can also be implemented for loading and persisting
  the tape head so a re-crawl isn't necessary if the process is interrupted.

  ## Options

  When invoking `use Terminus.Planaria`, the following [`config`](`t:config/0`)
  options are accepted:

  * `:token` - Planaria Token. Required.
  * `:from` - The block height from which to crawl for transactions. Required.
  * `:query` - Full or shorthand [Bitquery](https://bitquery.planaria.network) map.
  * `:poll` - Interval (in seconds) to poll Bitbus for new blocks. Defaults to `300` (5 minutes).

  ## Supervision

  Each `Terminus.Planaria` will most commonly be started under your application's
  supervision tree. When you invoke `use Terminus.Planaria`, it automatically
  defines a `child_spec/1` function so your Planaria modules can be started
  directly under a supervisor.

  And this is where we can have some fun and take full advantage of Elixir's
  concurrency model. Why not run many Planarias concurrently in your app?

      children = [
        TwetchScraper,
        PreevScraper,
        WeathersvScraper
      ]

      Supervisor.start_link(children, strategy: :one_for_all)
  """
  require Logger
  use GenStage
  alias Terminus.{Bitbus,Bitsocket}


  defstruct mod: nil,
            crawl_sub: nil,
            listen_sub: nil,
            tape: %{head: 0, height: 0},
            config: %{poll: 300, query: %{}}


  @typedoc "Planaria state."
  @type t :: %__MODULE__{
    mod: atom,
    crawl_sub: {pid, GenStage.subscription_tag},
    listen_sub: {pid, GenStage.subscription_tag},
    tape: tape,
    config: config
  }

  @typedoc "Planaria config."
  @type config :: %{
    token: String.t,
    poll: integer,
    from: integer,
    query: map
  }

  @typedoc "Planaria tape."
  @type tape :: %{
    head: integer,
    height: integer
  }

  @typedoc "Planaria tape event."
  @type tape_event :: :start | :block

  @typedoc "Planaria transaction event."
  @type tx_event :: :block | :mempool


  @doc """
  Invoked for each new transaction seen by the Planaria.

  This is the main callback you will need to implement for your Planaria module.
  Typically it will be used to pull the necessary data from each transaction
  event and store it to a local database.

  When an unconfirmed transaction is seen the callback is invoked with the
  [`tx_event`](`t:tx_event/0`) of `:mempool`. For each confirmed transaction,
  the callback is invoked with the [`tx_event`](`t:tx_event/0`) of `:block`.
  The callback can return any value.

  ## Examples

      def handle_data(:block, txns) do
        txns
        |> Enum.map(&MyApp.Transaction.build/1)
        |> Repo.insert(on_conflict: :replace_all, conflict_target: :txid)
      end

      def handle_data(:mempool, txns) do
        txns
        |> Enum.map(&MyApp.Transaction.build/1)
        |> Repo.insert
      end
  """
  @callback handle_data(tx_event, list) :: any


  @doc """
  Invoked when a Planaria starts and also after each crawl of new blocks.

  This callback can be used to load and persist the tape head so a re-crawl
  isn't necessary if the process is interrupted.

  When a Planaria starts the callback is invoked with the [`tape_event`](`t:tape_event/0`)
  of `:start`. This provides an oppurtunity to load the current `:head` of the
  tape from a database and update the given [`tape`](`t:tape/0`).
  The callback must return `{:ok, tape}`.

  After each crawl of block data the callback in invoked with the [`tape_event`](`t:tape_event/0`)
  if `:block`. This allows us to store the [`tape`](`t:tape/0`)
  `:head`. In this case any return value is acceptable.

  ## Examples

  Load the `:head` from a database when the Planaria starts.

      def handle_tape(:start, tape) do
        tape = case MyApp.Config.get("tape_head") do
          {:ok, head} -> put_in(tape.head, head)
          _ -> tape
        end
        {:ok, tape}
      end

  Persist the `:head` after each crawl of new blocks.

      def handle_tape(:block, tape) do
        MyApp.Config.put("tape_head", tape.head)
      end
  """
  @callback handle_tape(tape_event, tape) :: {:ok, tape} | any


  @doc false
  defmacro __using__(config \\ []) do
    quote location: :keep, bind_quoted: [config: config] do
      alias Terminus.Planaria

      @behaviour Planaria

      @doc false
      def child_spec(opts) do
        spec = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]}
        }
        Supervisor.child_spec(spec, [])
      end

      @doc false
      def start_link(opts \\ []) do
        Planaria.start_link(__MODULE__, unquote(Macro.escape(config)), opts)
      end

      @doc false
      def start(opts \\ []) do
        Planaria.start(__MODULE__, unquote(Macro.escape(config)), opts)
      end

      @doc false
      def handle_data(type, txns),
        do: Logger.debug inspect({type, length(txns)})

      @doc false
      def handle_tape(:type, tape), do: {:ok, tape}


      defoverridable handle_tape: 2, handle_data: 2

    end
  end


  @doc """
  Starts a `Terminus.Planaria` process linked to the current process.

  This is often used to start the Planaria as part of a supervision tree.
  """
  @spec start_link(atom, config, keyword) :: GenServer.on_start
  def start_link(module, config, options) do
    GenStage.start_link(__MODULE__, {module, config}, options)
  end


  @doc """
  Starts a `Terminus.Planaria` process without links (outside of a supervision
  tree).

  See `start_link/3` for more information.
  """
  @spec start(atom, config, keyword) :: GenServer.on_start
  def start(module, config, options) do
    GenStage.start(__MODULE__, {module, config}, options)
  end


  # Callbacks


  @impl true
  def init({module, config}) do
    state = %__MODULE__{mod: module}
    |> Map.update!(:config, & Map.merge(&1, struct(Config, config)))

    tape = state.tape
    |> Map.put(:head, state.config.from)

    case apply(state.mod, :handle_tape, [:start, tape]) do
      {:ok, tape} ->
        Logger.info "#{ state.mod } starting..."
        Process.send_after(self(), :status, 500)
        state = put_in(state.tape, tape)
        {:consumer, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @impl true
  def handle_cast(:crawl, %__MODULE__{tape: tape, config: config} = state) do
    Logger.info "#{ state.mod } starting crawl from #{ tape.head }"

    query = config.query
    |> Terminus.Streamer.normalize_query
    |> update_in(["q", "find"], & default_find_params(&1, tape))
    |> update_in(["q", "sort"], &default_sort_params/1)

    case Bitbus.crawl(query, token: config.token, stage: true) do
      {:ok, pid} ->
        GenStage.async_subscribe(self(), to: pid, cancel: :transient, mode: :crawl)
        {:noreply, [], state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  def handle_cast(:listen, %__MODULE__{config: config} = state) do
    Logger.info "#{ state.mod } starting listen"

    query = config.query
    |> Terminus.Streamer.normalize_query

    case Bitsocket.listen(query, stage: true) do
      {:ok, pid} ->
        GenStage.async_subscribe(self(), to: pid, mode: :listen)
        {:noreply, [], state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end


  # TODO
  defp default_find_params(nil, %{} = tape),
    do: %{"blk.i" => %{"$gt" => tape.head}}
  defp default_find_params(%{} = find, %{} = tape),
    do: Map.put(find, "blk.i", %{"$gt" => tape.head})


  # TODO
  defp default_sort_params(nil),
    do: %{"blk.i" => 1}
  defp default_sort_params(%{} = sort),
    do: Map.put(sort, "blk.i", 1)


  @impl true
  def handle_info(:status, %__MODULE__{tape: tape, config: config} = state) do
    Logger.info "#{ state.mod } checking chain status"

    case Bitbus.status do
      {:ok, status} ->
        tape = put_in(tape.height, status["height"])
        state = put_in(state.tape, tape)

        cond do
          tape.height > tape.head && is_nil(state.crawl_sub) ->
            GenStage.cast(self(), :crawl)
          is_nil(state.listen_sub) ->
            GenStage.cast(self(), :listen)
        end

        Process.send_after(self(), :status, config.poll * 1000)
        {:noreply, [], state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end


  @impl true
  def handle_subscribe(:producer, opts, from, %__MODULE__{} = state) do
    Logger.info "#{ state.mod } subscribed to #{ inspect(from) }"

    state = case Keyword.get(opts, :mode) do
      :crawl  -> put_in(state.crawl_sub, from)
      :listen -> put_in(state.listen_sub, from)
    end
    {:automatic, state}
  end


  @impl true
  def handle_events(events, from, %__MODULE__{crawl_sub: crawl_sub} = state)
    when from == crawl_sub,
    do: process_events(events, :block, state)

  def handle_events(events, from, %__MODULE__{listen_sub: listen_sub} = state)
    when from == listen_sub,
    do: process_events(events, :mempool, state)


  # TODO
  defp process_events(events, type, state) do
    apply(state.mod, :handle_data, [type, events])
    {:noreply, [], state}
  end


  @impl true
  def handle_cancel({:down, :normal}, from, %__MODULE__{crawl_sub: crawl_sub, tape: tape} = state)
    when from == crawl_sub
  do
    Logger.info "#{__MODULE__} Finished crawl to #{ tape.height }"

    state = Map.merge(state, %{
      crawl_sub: nil,
      tape: put_in(tape.head, tape.height)
    })

    apply(state.mod, :handle_tape, [:update, state.tape])

    if is_nil(state.listen_sub),
      do: GenStage.cast(self(), :listen)
    
    {:noreply, [], state}
  end

end