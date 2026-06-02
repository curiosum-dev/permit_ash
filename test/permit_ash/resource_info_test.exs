defmodule Permit.Ash.ResourceInfoTest do
  use ExUnit.Case, async: true

  alias Permit.Ash.Resource.Info
  alias Permit.Ash.Test.{Post, PostActorFirst}

  describe "action_mapping/2 is order-independent" do
    test "finds mapping when map_action is declared before for_actor (Post)" do
      assert {:ok, :update} = Info.action_mapping(Post, :publish)
    end

    test "finds mapping when for_actor is declared before map_action (PostActorFirst)" do
      assert {:ok, :update} = Info.action_mapping(PostActorFirst, :publish)
    end

    test "returns :error for unmapped action names" do
      assert :error = Info.action_mapping(Post, :nonexistent)
      assert :error = Info.action_mapping(PostActorFirst, :nonexistent)
    end
  end
end
