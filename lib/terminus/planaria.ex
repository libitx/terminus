defmodule Terminus.Planaria do
  @moduledoc """
  TODO
  """
  require Logger
  use GenStage
  alias Terminus.{Bitbus,Bitsocket}
  alias __MODULE__.{Config,Tape}



  defstruct mod: nil,
            crawl_sub: nil,
            listen_sub: nil,
            tape: %Tape{},
            config: %Config{}


  @typedoc "TODO"
  @type t :: %__MODULE__{
    mod: atom,
    crawl_sub: {pid, GenStage.subscription_tag},
    listen_sub: {pid, GenStage.subscription_tag},
    tape: Tape.t,
    config: Config.t
  }


  @doc """
  TODO
  """
  @callback handle_tape(:get | :put, Tape.t) :: {:ok, Tape.t} | any

  
  @doc """
  TODO
  """
  @callback handle_data(:confirmed | :mempool, map) :: any


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
      def handle_tape(_, tape), do: {:ok, tape}

      @doc false
      def handle_data(type, tx),
        do: Logger.info inspect({type, tx["tx"]["h"]})


      defoverridable handle_tape: 2, handle_data: 2

    end
  end


  @doc """
  TODO
  """
  def start_link(module, config, options) do
    GenStage.start_link(__MODULE__, {module, config}, options)
  end


  @doc """
  TODO
  """
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
  defp default_find_params(nil, %Tape{} = tape),
    do: %{"blk.i" => %{"$gt" => tape.head}}
  defp default_find_params(%{} = find, %Tape{} = tape),
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
    do: process_events(events, :confirmed, state)

  def handle_events(events, from, %__MODULE__{listen_sub: listen_sub} = state)
    when from == listen_sub,
    do: process_events(events, :mempool, state)


  # TODO
  defp process_events(events, type, state) do
    Enum.each(events, & apply(state.mod, :handle_data, [type, &1]))
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