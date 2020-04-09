defmodule Terminus.Bitbus do
  @moduledoc """
  TODO
  """
  use Terminus.HTTPStream, host: "txo.bitbus.network"


  @doc """
  TODO
  """
  @spec crawl(map | String.t, keyword, function | nil) ::
    :ok | Enumerable.t | pid
  def crawl(query, opts \\ [], ondata \\ nil)

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
  TODO
  """
  @spec status() :: map
  def status do
    case stream("GET", "/status", nil) do
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