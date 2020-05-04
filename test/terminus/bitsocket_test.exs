defmodule Terminus.BitsocketTest do
  use ExUnit.Case
  alias Terminus.Bitsocket

  @host "http://localhost:8088"


  describe "Bitsocket.crawl/3" do
    test "must return a stream" do
      {:ok, res} = Bitsocket.crawl(%{"q" => "test"}, token: "test", host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      {:ok, res} = Bitsocket.crawl(%{"q" => "test"}, token: "test", host: @host, stage: true)
      assert is_pid(res)
    end

    test "must run callback on stream" do
      Bitsocket.crawl(%{"q" => "test"}, [token: "test", host: @host], fn tx ->
        assert String.length(tx["tx"]["h"]) == 64
      end)
    end
  end


  describe "Bitsocket.crawl!/3" do
    test "must return a stream" do
      res = Bitsocket.crawl!(%{"q" => "test"}, token: "test", host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      res = Bitsocket.crawl!(%{"q" => "test"}, token: "test", host: @host, stage: true)
      assert is_pid(res)
    end
  end


  describe "Bitsocket.fetch/2" do
    test "must return an enumerable" do
      {:ok, res} = Bitsocket.fetch(%{"q" => "test"}, token: "test", host: @host)
      assert is_list(res)
      assert length(res) == 5
    end

    @tag capture_log: true
    test "must return an error when no token" do
      {:error, reason} = Bitsocket.fetch(%{"q" => "test"}, host: @host)
      assert reason == %Terminus.HTTP.Error{status: 403}
    end
  end


  describe "Bitsocket.fetch!/2" do
    test "must return an enumerable" do
      res = Bitsocket.fetch!(%{"q" => "test"}, token: "test", host: @host)
      assert is_list(res)
      assert length(res) == 5
    end

    @tag capture_log: true
    test "must throw an error when no token" do
      assert_raise Terminus.HTTP.Error, "HTTP Error: Forbidden", fn ->
        Bitsocket.fetch!(%{"q" => "test"}, host: @host)
      end
    end
  end


  describe "Bitsocket.listen/3" do
    test "must return a stream" do
      {:ok, res} = Bitsocket.listen(%{"q" => "test"}, host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      {:ok, res} = Bitsocket.listen(%{"q" => "test"}, host: @host, stage: true)
      assert is_pid(res)
    end

    test "must run callback on stream" do
      # OK so this is a bit funky. The SSE request stays forever waiting for future
      # events and I wasn't sure how to exit the loop, do I hacked together this
      # horrible raise and rescue affair to ensure the assertions get tested.
      try do
        Bitsocket.listen("test", [token: "test", host: @host], fn tx ->
          assert String.length(tx["tx"]["h"]) == 64
          raise "get me outta here"
        end)
      rescue
        err ->
          assert err.message == "get me outta here"
      end
    end
  end


  describe "Bitsocket.listen!/3" do
    test "must return a stream" do
      res = Bitsocket.listen!(%{"q" => "test"}, host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      res = Bitsocket.listen!(%{"q" => "test"}, host: @host, stage: true)
      assert is_pid(res)
    end
  end
  
end
