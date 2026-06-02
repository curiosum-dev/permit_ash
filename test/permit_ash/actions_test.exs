defmodule Permit.Ash.ActionsTest do
  use ExUnit.Case, async: true

  alias Permit.Ash.Test.AshActions

  describe "grouping_schema/0" do
    test "contains all action names from all domain resources" do
      schema = AshActions.grouping_schema()

      # Post actions: :read, :destroy, :create, :update, :publish
      # Author actions: :read, :destroy, :create  (deduplicated)
      for action <- [:read, :destroy, :create, :update, :publish] do
        assert Map.has_key?(schema, action),
               "expected #{inspect(action)} in grouping schema, got: #{inspect(Map.keys(schema))}"
      end
    end

    test "all actions are standalone — empty dependency lists" do
      schema = AshActions.grouping_schema()
      assert Enum.all?(schema, fn {_, deps} -> deps == [] end)
    end

    test "deduplicates action names that appear across multiple resources" do
      schema = AshActions.grouping_schema()
      keys = Map.keys(schema)
      # :read, :destroy, :create appear on both Post and Author
      assert Enum.count(keys, &(&1 == :read)) == 1
      assert Enum.count(keys, &(&1 == :create)) == 1
      assert Enum.count(keys, &(&1 == :destroy)) == 1
    end
  end

  describe "list_groups/1" do
    test "returns all unique action atoms" do
      groups = Permit.Actions.list_groups(AshActions)
      assert :read in groups
      assert :update in groups
      assert :publish in groups
    end
  end
end
