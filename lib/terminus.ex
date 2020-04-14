defmodule Terminus do
  @moduledoc """
  Terminus allows you to crawl and subscribe to Bitcoin transaction events using
  [Bitbus](https://bitbus.network) and [Bitsocket](https://bitsocket.network).

  > **terminus** &mdash; noun
  > * the end of a railway or other transport route, or a station at such a point; a terminal.
  > * a final point in space or time; an end or extremity.

  Terminus provides a single unified interface for crawling and querying both
  Bitbus and Bitsocket in a highly performant manner. It takes full advantage of
  Elixir processes so multiple concurrent queries can be streamed to your
  application. Terminus may well be the most powerful way of querying Bitcoin in
  the Universe!

  ## Bitbus

  Bitbus is a powerful API that allows you to crawl a filtered subset of the
  Bitcoin blockchain. Bitbus indexes blocks, thus can be used to crawl
  **confirmed** transactions.

  > We run a highly efficient bitcoin crawler which indexes the bitcoin
  > blockchain. Then we expose the index as an API so anyone can easily crawl
  > ONLY the subset of bitcoin by crawling bitbus.

  Each returned transaction document has the following schema:

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

  ## Bitsocket

  Bitsocket sends you realtime events from the Bitcoin blockchain. It uses
  [Server Sent Events](https://en.wikipedia.org/wiki/Server-sent_events) to
  stream new **unconfirmed** transactions as soon as they appear on the Bitcoin
  network.

  > Bitsocket is like Websocket, but for Bitcoin. With just a single Bitsocket
  > connection, you get access to a live, filterable stream of all transaction
  > events across the entire bitcoin peer network.

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

  In slight different to Bitbus, Bitsocket offers alternative endpoints for
  querying documents with inputs and outputs represented using either the
  [TXO schema](https://bitquery.planaria.network/#/?id=txo) OR the
  [BOB schema](https://bitquery.planaria.network/#/?id=bob).

  ## Authentication

  Both Bitbus and Bitsocket  require a token to authenticate requests. *(The Bitsocket `listen`
  API currenrly doesn't require a token but that is likely to change).* Currently
  tokens are free with no usage limits. *(Also likely to change)*

  **[Get your Planaria Token](https://token.planaria.network).**

  ## Query language

  Both APIs use the same MongoDB-like query language, known as
  [Bitquery](https://bitquery.planaria.network). This means Terminus can be used
  to crawl both Bitbus and Bitsocket concurrently with the same query.

      iex> Terminus.crawl!(%{
      ...>   find: %{ "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn" },
      ...>   sort: %{ "blk.i": -1, "timestamp": -1 },
      ...>   limit: 10
      ...> }, token: token)
      %{
        "c" => [%{}, ...],
        "u" => [%{}, ...],
      }

  ## Using Terminus




  """

  @typedoc "On-data callback function."
  @type callback :: function

  @token "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.eyJzdWIiOiIxOVp2eUtHNWNOdDJiZHVLSDRjclp6Sm5lZkJYcmJLaGIyIiwiaXNzdWVyIjoiZ2VuZXJpYy1iaXRhdXRoIn0.SDk2Yit5R1dqeXc0WklHZlNDd1NwUmloM2tNRUVtRnRGZld4ZWhBRVhjWnhmWkMzR1RmanpkdEVnNWJ1VEk0cm92NFROMk5CYkl2UnlmR1lBSFYzRlYwPQ"
  @query_a %{
    q: %{
      find: %{
        "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn",
        "blk.i" => %{ "$gt" => 609000 }
      },
      sort: %{ "blk.i": -1 },
      limit: 5
    }
  }

  @query_b %{
    q: %{
      find: %{
        "out.s2" => "1LtyME6b5AnMopQrBPLk4FGN8UBuhxKqrn"
      },
      limit: 5
    }
  }


  def test_a1 do
    Terminus.Bitbus.crawl(@query_a, token: @token)
  end

  def test_a2 do
    Terminus.Bitbus.crawl!(@query_a, token: @token)
    |> Enum.to_list
  end

  def test_a3 do
    Terminus.Bitbus.crawl(@query_a, [token: @token], fn tx ->
      IO.puts "Yo we got a TX"
      IO.puts tx["tx"]["h"]
    end)
  end



  def test_b1 do
    Terminus.Bitsocket.crawl(@query_b, token: @token)
  end

  def test_b2 do
    Terminus.Bitsocket.crawl!(@query_b, token: @token)
    |> Enum.to_list
  end

  def test_b3 do
    Terminus.Bitsocket.crawl(@query_b, [token: @token], fn tx ->
      IO.puts "Yo we got a TX"
      IO.puts tx["tx"]["h"]
    end)
  end



  def test_c1 do
    Terminus.Bitsocket.listen(@query_b)
  end

  def test_c2 do
    Terminus.Bitsocket.listen(@query_b, fn tx ->
      IO.puts "Yo we got a TX"
      IO.puts tx["tx"]["h"]
    end)
  end


  def test_d1 do
    Terminus.Bitbus.fetch(%{q: %{find: %{"tx.h" => "13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a"}}}, token: @token)
  end
end


defmodule Terminus.Message do
  @moduledoc false
  defstruct id: nil, event: "message", data: ""
end

defmodule Terminus.Response do
  @moduledoc false
  defstruct status: nil, headers: [], data: ""
end

defmodule Terminus.HTTPError do
  @moduledoc false
  defexception [:status]
  def message(exception),
    do: "HTTP Error: #{:httpd_util.reason_phrase(exception.status)}"
end