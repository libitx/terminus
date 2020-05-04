defmodule Terminus.OmniTest do
  use ExUnit.Case
  alias Terminus.Omni

  @host "http://localhost:8088"
  @query %{
    find: %{"out.s2" => "test"}
  }


  describe "Omni.fetch/2" do
    test "must return a map" do
      {:ok, res} = Omni.fetch(@query, token: "test", host: @host)
      assert is_map(res)
      assert length(res.c) == 5
      assert length(res.u) == 5
    end

    @tag capture_log: true
    test "must return an error when no token" do
      {:error, reason} = Omni.fetch(@query, host: @host)
      assert reason == %Terminus.HTTP.Error{status: 403}
    end
  end


  describe "Omni.fetch!/2" do
    test "must return a map" do
      res = Omni.fetch!(@query, token: "test", host: @host)
      assert is_map(res)
      assert length(res.c) == 5
      assert length(res.u) == 5
    end

    @tag capture_log: true
    test "must throw an error when no token" do
      assert_raise Terminus.HTTP.Error, "HTTP Error: Forbidden", fn ->
        Omni.fetch!(@query, host: @host)
      end
    end
  end


  describe "Omni.find/2" do
    test "must return a transaction" do
      {:ok, res} = Omni.find("test", token: "test", host: @host)
      assert is_map(res)
      assert String.length(res["tx"]["h"]) == 64
    end

    @tag capture_log: true
    test "must return an error when no token" do
      {:error, reason} = Omni.find("test", host: @host)
      assert reason == %Terminus.HTTP.Error{status: 403}
    end
  end


  describe "Omni.find!/2" do
    test "must return a map" do
      res = Omni.find!("test", token: "test", host: @host)
      assert is_map(res)
      assert String.length(res["tx"]["h"]) == 64
    end

    @tag capture_log: true
    test "must throw an error when no token" do
      assert_raise Terminus.HTTP.Error, "HTTP Error: Forbidden", fn ->
        Omni.find!("test", host: @host)
      end
    end
  end
end