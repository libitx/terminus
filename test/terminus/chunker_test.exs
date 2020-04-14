defmodule Terminus.ChunkerTest do
  use ExUnit.Case
  alias Terminus.Chunker

  describe "Chunker.handle_chunk/2" do
    test "must return raw data as list" do
      {events, data} = Chunker.handle_chunk("foobar", :raw)
      assert events == ["foobar"]
      assert data == ""
    end

    test "must return ndjson as list" do
      {events, data} = Chunker.handle_chunk("{\"foo\":\"bar\"}\n{\"foo\":\"bar\"}\n{\"fo", :ndjson)
      assert length(events) == 2
      assert data == "{\"fo"
    end

    test "must return eventsource as list" do
      {events, data} = Chunker.handle_chunk("id: 123\nevent: message\ndata: {\"type\":\"push\",\"data\":[\"foobar\"]}\n", :eventsource)
      assert events == ["foobar"]
      assert data == ""
    end
  end

end