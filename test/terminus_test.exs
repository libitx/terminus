defmodule TerminusTest do
  use ExUnit.Case
  doctest Terminus

  test "greets the world" do
    assert Terminus.hello() == :world
  end
end
