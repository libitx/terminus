defmodule Terminus.BitbusTest do
  use ExUnit.Case
  alias Terminus.Bitbus

  @host "http://localhost:8088"


  describe "Bitbus.crawl/3" do
    test "must return a stream" do
      {:ok, res} = Bitbus.crawl(%{"q" => "test"}, token: "test", host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      {:ok, res} = Bitbus.crawl(%{"q" => "test"}, token: "test", host: @host, stage: true)
      assert is_pid(res)
    end

    test "must run callback on stream" do
      Bitbus.crawl(%{"q" => "test"}, [token: "test", host: @host], fn tx ->
        assert String.length(tx["tx"]["h"]) == 64
      end)
    end
  end


  describe "Bitbus.crawl!/3" do
    test "must return a stream" do
      res = Bitbus.crawl!(%{"q" => "test"}, token: "test", host: @host)
      assert is_function(res)
      assert inspect(res) |> String.match?(~r/Stream/)
    end

    test "must return a pid" do
      res = Bitbus.crawl!(%{"q" => "test"}, token: "test", host: @host, stage: true)
      assert is_pid(res)
    end
  end


  describe "Bitbus.fetch/2" do
    test "must return an enumerable" do
      {:ok, res} = Bitbus.fetch(%{"q" => "test"}, token: "test", host: @host)
      assert is_list(res)
      assert length(res) == 5
    end

    @tag capture_log: true
    test "must return an error when no token" do
      {:error, reason} = Bitbus.fetch(%{"q" => "test"}, host: @host)
      assert reason == %Terminus.HTTP.Error{status: 403}
    end
  end


  describe "Bitbus.fetch!/2" do
    test "must return an enumerable" do
      res = Bitbus.fetch!(%{"q" => "test"}, token: "test", host: @host)
      assert is_list(res)
      assert length(res) == 5
    end

    @tag capture_log: true
    test "must throw an error when no token" do
      assert_raise Terminus.HTTP.Error, "HTTP Error: Forbidden", fn ->
        Bitbus.fetch!(%{"q" => "test"}, host: @host)
      end
    end
  end


  describe "Bitbus.status/1" do
    test "must return current status" do
      {:ok, res} = Bitbus.status(host: @host)
      assert Map.keys(res) |> length == 8
      assert Map.keys(res) |> Enum.member?("hash")
      assert Map.keys(res) |> Enum.member?("height")
      assert Map.keys(res) |> Enum.member?("time")
    end
  end


  describe "Bitbus.status!/1" do
    test "must return current status" do
      res = Bitbus.status!(host: @host)
      assert Map.keys(res) |> length == 8
      assert Map.keys(res) |> Enum.member?("hash")
      assert Map.keys(res) |> Enum.member?("height")
      assert Map.keys(res) |> Enum.member?("time")
    end
  end
  
end
