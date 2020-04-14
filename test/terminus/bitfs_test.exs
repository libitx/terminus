defmodule Terminus.BitFSTest do
  use ExUnit.Case
  alias Terminus.BitFS


  describe "BitFS.fetch/2" do
    test "must return an binary" do
      {:ok, res} = BitFS.fetch("13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4", host: "127.0.0.1")
      assert is_binary(res)
      assert byte_size(res) == 578
    end

    @tag capture_log: true
    test "must return an error when file" do
      {:error, reason} = BitFS.fetch("notfound", host: "127.0.0.1")
      assert reason == "HTTP Error: Object Not Found"
    end
  end


  describe "BitFS.fetch!/2" do
    test "must return an enumerable" do
      res = BitFS.fetch!("13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4", host: "127.0.0.1")
      assert is_binary(res)
      assert byte_size(res) == 578
    end

    @tag capture_log: true
    test "must throw an error when no file" do
      assert_raise Terminus.HTTPError, "HTTP Error: Object Not Found", fn ->
        BitFS.fetch!("notfound", host: "127.0.0.1")
      end
    end
  end
  
end
