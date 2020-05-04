defmodule Terminus.Omni do
  @moduledoc """
  Module for conveniently fetching data from both [Bitbus](https://bitbus.network)
  and [Bitsocket](https://bitbus.network) concurrently.

  `Terminus.Omni` replicates the functionality of legacy Planaria APIs by allowing
  you to query for both confirmed and unconfirmed transactions in one call. HTTP
  requests to both APIs occur concurrently and a combined result is returned when
  both APIs have yielded a response.

  Mempool transactions are intelligently handled. The Bitsocket event database
  is queried to safely gather enough transactions to cover the time period since
  the last block, and then cross-referenced with confirmed transactions to
  ensure there are no duplicates. It just... works!

  ## Examples

  Use `fetch/2` to query for a combined set of confirmed and unconfimred
  transactions.

      iex> Terminus.Omni.fetch(%{
      ...>   find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" },
      ...>   limit: 5
      ...> }, token: token)
      {:ok, %{
        c: [...], # 5 confirmed tx
        u: [...], # 5 unconfirmed tx
      }}
  
  Alterntivly, `find/2` allows for a single transaction to be easily found by
  it's [`txid`](`t:Terminus.txid/0`), irrespective of whether the transaction is
  confirmed or in the mempool. 

      iex> Terminus.Omni.find(txid, token: token)
      {:ok, %{
        "tx" => %{"h" => "fca7bdd7658613418c54872212811cf4c5b4f8ee16864eaf70cb1393fb0df6ca"},
        ...
      }}
  """

  # Using exponential distribution with mean of 600 seconds, 99% of blocks are
  # mined within 2,765 seconds - @Deadloch
  @safe_unconfirmed_window 2800


  @doc """
  Crawls Bitbus and Bitsocket for transactions using the given query and returns
  a map containing both confirmed and mempool transactions.

  Returns the result in an `:ok` / `:error` tuple pair.

  If no limit is specified in the given [`bitquery`](`t:Terminus.bitquery/0`)
  map, a default limit of `20` is added to the query. This limit is applied to
  both sets of results, meaning a maximum of 40 unique transactions may be
  returned.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitbus host. Defaults to `:txo`.

  ## Examples

  Get the 5 latest confirmed and unconfirmed WeatherSV transactions.

      iex> Terminus.Omni.fetch(%{
      ...>   find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" },
      ...>   limit: 5
      ...> }, token: token)
      {:ok, %{
        c: [...], # 5 confirmed tx
        u: [...], # 5 unconfirmed tx
      }}
  """
  @spec fetch(Terminus.bitquery, keyword) ::
    {:ok, map} |
    {:error, Exception.t}
  def fetch(query, options \\ [])

  def fetch(query, options) when is_binary(query),
    do: query |> Jason.decode! |> fetch(options)

  def fetch(%{} = query, options) do
    query = query
    |> Terminus.HTTPStream.normalize_query
    |> update_in(["q", "limit"], &default_limit/1)

    timeout = Keyword.get(options, :timeout, :infinity)

    tasks = [bb_task, bs_task] = [
      bitbus_task(query, options),
      bitsocket_task(query, options)
    ]

    result = Task.yield_many(tasks, timeout)
    |> Enum.reduce_while(%{}, fn
      # Put Bitbus txns directly into results
      {^bb_task, {:ok, {:ok, txns}}}, res ->
        {:cont, Map.put(res, :c, txns)}
      
      # Filter Bitsocket to remove dupes and reinforce the limit
      {^bs_task, {:ok, {:ok, txns}}}, res ->
        confimed_txids = res.c
        |> Enum.map(& &1["tx"]["h"])
        {txns, _} = txns
        |> Enum.reject(& Enum.member?(confimed_txids, &1["tx"]["h"]))
        |> Enum.split(query["q"]["limit"])
        {:cont, Map.put(res, :u, txns)}
      
      {_task, {:ok, {:error, reason}}}, _res ->
        {:halt, {:error, reason}}
      
      {_task, {:error, reason}}, _res ->
        {:halt, {:error, reason}}
      
      {task, nil}, _res ->
        Task.shutdown(task, :brutal_kill)
        {:halt, {:error, %RuntimeError{message: "Fetch request timed out."}}}
    end)

    case result do
      {:error, reason} ->
        {:error, reason}
      
      result ->
        {:ok, result}
    end
  end


  @doc """
  As `fetch/2` but returns the result or raises an exception if it fails.
  """
  @spec fetch!(Terminus.bitquery, keyword) :: map
  def fetch!(query, options \\ []) do
    case fetch(query, options) do
      {:ok, data} ->
        data

      {:error, error} ->
        raise error
    end
  end


  @doc """
  Query Bitbus and Bitsocket for a single transaction by the given [`txid`](`t:Terminus.txid/0`).

  Returns the result in an `:ok` / `:error` tuple pair.

  ## Options

  The accepted options are:

  * `token` - Planaria authentication token. **Required**.
  * `host` - The Bitbus host. Defaults to `:txo`.

  ## Examples

      iex> Terminus.Omni.find(txid, token: token)
      {:ok, %{
        "tx" => %{"h" => "fca7bdd7658613418c54872212811cf4c5b4f8ee16864eaf70cb1393fb0df6ca"},
        ...
      }}
  """
  @spec find(Terminus.txid, keyword) :: map  
  def find(txid, options \\ []) do
    query = %{
      "find" => %{"tx.h" => txid},
      "limit" => 1
    }

    case fetch(query, options) do
      {:ok, %{c: c, u: u}} ->
        {:ok, List.first(c ++ u)}

      {:error, error} ->
        {:error, error}
    end
  end


  @doc """
  As `find/2` but returns the result or raises an exception if it fails.
  """
  @spec find!(Terminus.txid, keyword) :: map
  def find!(query, options \\ []) do
    case find(query, options) do
      {:ok, data} ->
        data

      {:error, error} ->
        raise error
    end
  end


  # The asynchronous Bitbus fetch task
  defp bitbus_task(query, options) do
    query = query
    |> update_in(["q", "sort"], &default_bitbus_sort/1)

    Task.async(Terminus.Bitbus, :fetch, [query, options])
  end


  # The asynchronous Bitsocket fetch task
  # Checks the last ~46 minutes from the event database and doubles the limit to
  # ensure deduplicaion still leaves enough transactions.
  defp bitsocket_task(query, options) do
    mempool_window = Keyword.get(options, :mempool_window, @safe_unconfirmed_window)
    ts = :os.system_time(:millisecond) - (mempool_window * 1000)

    query = query
    |> update_in(["q", "find"], & Map.put(&1, "timestamp", %{"$gt" => ts}))
    |> update_in(["q", "limit"], & &1 * 2)
    |> update_in(["q", "sort"], &default_bitsocket_sort/1)
    
    Task.async(Terminus.Bitsocket, :fetch, [query, options])
  end


  # Puts the default limit into the query
  defp default_limit(nil), do: 20
  defp default_limit(limit), do: limit


  # Puts the default sort params into the Bitbus query
  defp default_bitbus_sort(nil), do: %{"blk.i" => -1}
  defp default_bitbus_sort(sort), do: sort


  # Puts the default sort params into the Bitsocket query
  defp default_bitsocket_sort(nil), do: %{"timestamp" => -1}
  defp default_bitsocket_sort(sort), do: sort

end