defmodule Permit.Ash.DomainPermissionsTest do
  use ExUnit.Case, async: true

  alias Permit.Ash.Test.{Author, DomainPermissions, Post}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_post!(attrs \\ %{}) do
    defaults = %{title: "untitled", user_id: nil, published: false, score: 0}

    Post
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(authorize?: false)
  end

  defp create_author!(attrs \\ %{}) do
    Author
    |> Ash.Changeset.for_create(:create, Map.merge(%{active: true}, attrs))
    |> Ash.create!(authorize?: false)
  end

  defp granted?(actor, action, record) do
    actor
    |> DomainPermissions.can()
    |> Permit.Permissions.granted?(action, record, actor)
  end

  # ---------------------------------------------------------------------------
  # Nil / no-match actor
  # ---------------------------------------------------------------------------

  describe "unmatched actor" do
    test "has no permissions on Post" do
      post = create_post!(%{user_id: 1})
      refute granted?(%{role: :stranger}, :read, post)
      refute granted?(%{role: :stranger}, :update, post)
    end
  end

  # ---------------------------------------------------------------------------
  # admin role — action(:all, []) expands to every action group
  # ---------------------------------------------------------------------------

  describe "admin role" do
    test "can read any post" do
      post = create_post!(%{user_id: 2, published: false})
      assert granted?(%{role: :admin}, :read, post)
    end

    test "can create a post" do
      post = create_post!()
      assert granted?(%{role: :admin}, :create, post)
    end

    test "can update any post" do
      post = create_post!(%{user_id: 2})
      assert granted?(%{role: :admin}, :update, post)
    end

    test "can destroy any post" do
      post = create_post!(%{user_id: 2})
      assert granted?(%{role: :admin}, :destroy, post)
    end

    test "has permission on custom mapped action (publish → update)" do
      post = create_post!()
      # :publish is in the AshActions grouping schema so action(:all, []) covers it too.
      assert granted?(%{role: :admin}, :publish, post)
    end
  end

  # ---------------------------------------------------------------------------
  # owner role — conditional rules from for_actor
  # ---------------------------------------------------------------------------

  describe "owner role — conditional rules" do
    test "can read own post" do
      post = create_post!(%{user_id: 1})
      assert granted?(%{id: 1, role: :owner}, :read, post)
    end

    test "can read another user's post (unconditional read in the owner block)" do
      post = create_post!(%{user_id: 2})
      # read() with no conditions grants access to all posts for owner role
      assert granted?(%{id: 1, role: :owner}, :read, post)
    end

    test "can update own post" do
      post = create_post!(%{user_id: 1})
      assert granted?(%{id: 1, role: :owner}, :update, post)
    end

    test "cannot update another user's post" do
      post = create_post!(%{user_id: 2})
      refute granted?(%{id: 1, role: :owner}, :update, post)
    end

    test "can create a post (unconditional create in the owner block)" do
      post = create_post!()
      assert granted?(%{id: 1, role: :owner}, :create, post)
    end

    test "cannot destroy any post (no destroy rule)" do
      post = create_post!(%{user_id: 1})
      refute granted?(%{id: 1, role: :owner}, :destroy, post)
    end
  end

  # ---------------------------------------------------------------------------
  # Author resource — no Permit.Ash.Resource extension, so __permit_rules__ is
  # absent; DomainPermissions skips it silently.
  # ---------------------------------------------------------------------------

  describe "Author resource — no for_actor rules" do
    test "no actor has permissions on Author via DomainPermissions" do
      author = create_author!()
      refute granted?(%{role: :admin}, :read, author)
    end
  end

  # ---------------------------------------------------------------------------
  # Permit.Permissions compatibility — can/1 returns a usable %Permit.Permissions{}
  # ---------------------------------------------------------------------------

  describe "Permit.Permissions compatibility" do
    test "can/1 returns a %Permit.Permissions{} struct" do
      assert %Permit.Permissions{} = DomainPermissions.can(%{role: :admin})
    end

    test "conditions_map has entries for Post resource" do
      perms = DomainPermissions.can(%{id: 1, role: :owner})
      assert Map.has_key?(perms.conditions_map, {:read, Post})
      assert Map.has_key?(perms.conditions_map, {:update, Post})
      assert Map.has_key?(perms.conditions_map, {:create, Post})
      refute Map.has_key?(perms.conditions_map, {:destroy, Post})
    end
  end
end
