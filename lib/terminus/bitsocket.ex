defmodule Terminus.Bitsocket do
  @moduledoc """
  TODO
  """
  use Terminus.HTTPStream, host: "txo.bitsocket.network"


  @doc """
  TODO
  """
  @spec crawl(map | String.t, keyword, function | nil) ::
    :ok | Enumerable.t | pid
  def crawl(query, opts \\ [], ondata \\ nil)

  def crawl(%{} = query, opts, ondata),
    do: Jason.encode!(query) |> crawl(opts, ondata)

  def crawl(query, opts, ondata) when is_binary(query) do
    case stream("POST", "/crawl", query, opts) do
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
  @spec listen(map | String.t, function | nil) ::
    :ok | Enumerable.t | pid
  def listen(query, ondata \\ nil)

  def listen(%{} = query, ondata),
    do: Jason.encode!(query) |> listen(ondata)

  def listen(query, ondata) when is_binary(query) do
    path = "/s/" <> Base.encode64(query)
    case stream("GET", path, nil) do
      {:ok, pid} when is_pid(pid) ->
        pid

      {:ok, stream} ->
        stream
        |> HTTPStream.parse_eventsource
        |> HTTPStream.handle_data(ondata)

      {:error, error} ->
        raise error
    end
  end

end