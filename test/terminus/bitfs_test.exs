defmodule Terminus.BitFSTest do
  use ExUnit.Case
  alias Terminus.BitFS

  @host "http://localhost:8088"


  describe "BitFS.fetch/2" do
    test "must return an binary" do
      {:ok, res} = BitFS.fetch("13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4", host: @host)
      assert is_binary(res)
      assert byte_size(res) == 578
    end

    @tag capture_log: true
    test "must return an error when file" do
      {:error, reason} = BitFS.fetch("notfound", host: @host)
      assert reason == %Terminus.HTTP.Error{status: 404}
    end
  end


  describe "BitFS.fetch!/2" do
    test "must return an enumerable" do
      res = BitFS.fetch!("13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4", host: @host)
      assert is_binary(res)
      assert byte_size(res) == 578
    end

    @tag capture_log: true
    test "must throw an error when no file" do
      assert_raise Terminus.HTTP.Error, "HTTP Error: Object Not Found", fn ->
        BitFS.fetch!("notfound", host: @host)
      end
    end
  end
  
end
