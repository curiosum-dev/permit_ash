defmodule Permit.AshTest do
  use ExUnit.Case
  doctest Permit.Ash

  test "greets the world" do
    assert Permit.Ash.hello() == :world
  end
end
