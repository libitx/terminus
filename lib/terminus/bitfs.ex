defmodule Terminus.BitFS do
  @moduledoc """
  Module for interfacing with the [BitFS](https://bitfs.network) API.

  BitFS crawls the Bitcoin blockchain to find and store all the bitcoin script
  pushdata chunks **larger than 512 bytes**.

  > BitFS is an autonomous file system constructed from Bitcoin transactions.

  ## BitFS URI scheme

  Files are referenced using the [BitFS URI scheme](https://bitfs.network/about#urischeme).

      # bitfs://<TRANSACTION_ID>.(in|out).<SCRIPT_INDEX>.<CHUNK_INDEX>
      "bitfs://13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4"

  Terminus accepts given BitFS URI strings with or without the `bitfs://` prefix.

  ## Usage

  To simply return the binary data for any BitFS URI use `fetch/2`.

      iex> Terminus.BitFS.fetch(uri)
      {:ok, <<...>>}

  It is also possible to scan entire transactions and automatically fetch the
  binary data for any BitFS URIs discovered in the transaction. The binary data
  is added to the same output script at the same index with a `d` prefixed attribute.

      iex> tx = %{
      ...>   "out" => [%{
      ...>     "f4" => "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4",
      ...>     ...
      ...>   }]
      ...> }
      iex> Terminus.BitFS.scan_tx(tx)
      %{
        "out" => [%{
          "f4" => "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4",
          "d4" => <<...>>,
          ...
        }]
      }
  """
  use Terminus.HTTPStream, hosts: [bitfs: "https://x.bitfs.network"]


  @doc """
  Fetches the binary blob data from BitFS using the given BitFS URI.

  Returns the result in an `:ok` / `:error` tuple pair.

  By default the entire data response is returned, although optionally a
  streaming `t:Enumerable.t/0` can be returned or a linked
  GenStage [`pid`](`t:pid/0`).

  ## Options

  The accepted options are:

  * `stream` - Return a streaming `t:Enumerable.t/0`. Defaults to `false`.
  * `stage` - Return a linked GenStage [`pid`](`t:pid/0`). Defaults to `false`.

  ## Examples

  Files are references using the [BitFS URI scheme](https://bitfs.network/about#urischeme).

      # <TRANSACTION_ID>.(in|out).<SCRIPT_INDEX>.<CHUNK_INDEX>
      "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4"

  By default `Terminus.BitFS.fetch/2` returns the binary data of the file.

      iex> Terminus.BitFS.fetch(uri)
      {:ok, <<...>>}

  Optionally a streaming `t:Enumerable.t/0` can be returned.

      iex> Terminus.BitFS.fetch(uri, stream: true)
      {:ok, %Stream{}}

  Or the [`pid`](`t:pid/0`) of the GenStage producer can be returned. 

      iex> Terminus.BitFS.fetch(uri, stage: true)
      {:ok, #PID<>}
  """
  @spec fetch(Terminus.bitfs_uri, keyword) :: {:ok, binary} | {:error, Exception.t}
  def fetch(uri, options \\ [])

  def fetch("bitfs://" <> uri, options),
    do: fetch(uri, options)

  def fetch(uri, options) when is_binary(uri) do
    path = "/" <> uri
    options = Keyword.take(options, [:token, :host, :stream, :stage])

    case Keyword.get(options, :stream, false) do
      true ->
        request(:stream, "GET", path, options)
      
      _ ->
        request(:fetch, "GET", path, options)
    end
  end


  @doc """
  As `fetch/2` but returns the result or raises an exception if it fails.
  """
  @spec fetch!(Terminus.bitfs_uri, keyword) :: binary
  def fetch!(uri, options \\ []) do
    case fetch(uri, options) do
      {:ok, data} ->
        data

      {:error, error} ->
        raise error
    end
  end


  @doc """
  Scans the given transaction [`map`](`t:map/0`) and fetches the data for any
  BitFS URI references.

  Handles both `txo` and `bob` schema scripts.

  With `txo`, where a BitFS reference is found, the fetched data is added to the
  script at the same index as the reference. For example, if a BitFS reference is found
  at `f4`, that a new attribute `d4` is put into the script containing the data.

  With `bob`, for any cell containing a BitFS reference, a new attribute `d`
  is added to the cell containing the fetched data.

  ## Examples

      iex> tx = %{
      ...>   "out" => [%{
      ...>     "f4" => "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4",
      ...>     ...
      ...>   }]
      ...> }
      iex> Terminus.BitFS.scan_tx(tx)
      %{
        "out" => [%{
          "f4" => "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4",
          "d4" => <<...>>,
          ...
        }]
      }
  """
  @spec scan_tx(map) :: map
  def scan_tx(%{"out" => outputs} = tx) when is_list(outputs) do
    outputs = outputs
    |> Enum.map(&scan_script/1)
    put_in(tx["out"], outputs)
  end


  @doc """
  Scans the given transaction script [`map`](`t:map/0`) and fetches the data for
  any BitFS URI references.

  Handles both `txo` and `bob` schema scripts.
  
  With `txo`, where a BitFS reference is found, the fetched data is added to the
  script at the same index as the reference. For example, if a BitFS reference is found
  at `f4`, that a new attribute `d4` is put into the script containing the data.

  With `bob`, for any cell containing a BitFS reference, a new attribute `d`
  is added to the cell containing the fetched data.
  """
  @spec scan_script(map) :: map
  # Handles TXO script
  def scan_script(%{"len" => len} = out) when is_integer(len) do
    Map.keys(out)
    |> Enum.filter(& Regex.match?(~r/^f\d+/, &1))
    |> Enum.reduce(out, &reduce_txo/2)
  end

  # Handles BOB script
  def scan_script(%{"tape" => tape} = out) when is_list(tape) do
    tape = Enum.map(tape, &map_bob_cell/1)
    put_in(out["tape"], tape)
  end

  # Reduce TXO output
  defp reduce_txo(key, out) do
    [_, num] = String.split(key, "f")
    case fetch(out[key]) do
      {:ok, data} -> Map.put(out, "d"<>num, data)
      {:error, _} -> out
    end
  end

  # Map BOB cell
  defp map_bob_cell(%{"cell" => params} = cell) do
    params
    |> Enum.filter(& Map.has_key?(&1, "f"))
    |> Enum.reduce(cell, &reduce_bob/2)
  end

  # Reduce BOB cell
  defp reduce_bob(%{"f" => uri, "i" => i} = params, cell) do
    params = case fetch(uri) do
      {:ok, data} -> Map.put(params, "d", data)
      {:error, _} -> params
    end
    List.replace_at(cell["cell"], i, params)
  end

end