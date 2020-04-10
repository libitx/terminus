defmodule Terminus do
  @moduledoc """
  Documentation for `Terminus`.
  """

  @typedoc "On-data callback function."
  @type callback :: function

  @token ".eyJzdWIiOiIxOVp2eUtHNWNOdDJiZHVLSDRjclp6Sm5lZkJYcmJLaGIyIiwiaXNzdWVyIjoiZ2VuZXJpYy1iaXRhdXRoIn0.SDk2Yit5R1dqeXc0WklHZlNDd1NwUmloM2tNRUVtRnRGZld4ZWhBRVhjWnhmWkMzR1RmanpkdEVnNWJ1VEk0cm92NFROMk5CYkl2UnlmR1lBSFYzRlYwPQ"
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
    Terminus.Bitbus.crawl(@query_a, token: @token)
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
    Terminus.Bitsocket.crawl(@query_b, token: @token)
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
end


defmodule Terminus.Message do
  @moduledoc false
  defstruct id: nil, event: "message", data: ""
end

defmodule Terminus.Response do
  @moduledoc false
  defstruct status: nil, headers: []
end

defmodule Terminus.HTTPError do
  @moduledoc false
  defexception [:status]
  def message(exception),
    do: "HTTP Error: #{:httpd_util.reason_phrase(exception.status)}"
end