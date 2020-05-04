defmodule Terminus.HTTP.ResponseTest do
  use ExUnit.Case
  alias Terminus.HTTP.Response

  describe "Response.decode_data/2" do
    test "must return raw data as list" do
      {response, events} = %Response{data: "foobar"}
      |> Response.decode_data(as: :raw)
      assert events == ["foobar"]
      assert response.data == ""
    end

    test "must return ndjson as list" do
      {response, events} = %Response{data: "{\"foo\":\"bar\"}\n{\"foo\":\"bar\"}\n{\"fo"}
      |> Response.decode_data(as: :ndjson)
      assert length(events) == 2
      assert response.data == "{\"fo"
    end

    test "must return eventsource as list" do
      {response, events} = %Response{data: "id: 123\nevent: message\ndata: {\"type\":\"push\",\"data\":[\"foobar\"]}\n"}
      |> Response.decode_data(as: :eventsource)
      assert events == ["foobar"]
      assert response.data == ""
    end
  end

end