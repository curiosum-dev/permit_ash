defmodule Permit.Ash.AuthorizerTest do
  use ExUnit.Case, async: true

  # With private? true on the ETS data layer, each test process gets its own
  # isolated in-memory table — no setup/teardown needed.

  alias Permit.Ash.Test.Post

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ids(records), do: MapSet.new(records, & &1.id)

  defp create_post!(attrs \\ %{}) do
    defaults = %{title: "untitled", user_id: nil, published: false, score: 0}

    Post
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(authorize?: false)
  end

  defp read_posts!(actor) do
    Post
    |> Ash.Query.for_read(:read, %{}, actor: actor)
    |> Ash.read!()
  end

  defp read_posts(actor, opts \\ []) do
    Post
    |> Ash.Query.for_read(:read, %{}, [{:actor, actor} | opts])
    |> Ash.read()
  end

  # ---------------------------------------------------------------------------
  # Nil / anonymous actor
  # ---------------------------------------------------------------------------

  describe "nil actor" do
    test "read is forbidden" do
      create_post!()
      assert {:error, _} = read_posts(nil, authorize?: true)
    end

    test "create is forbidden" do
      assert {:error, _} =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "anon post"}, authorize?: true)
               |> Ash.create()
               |> IO.inspect()
    end
  end

  # ---------------------------------------------------------------------------
  # No permissions at all
  # ---------------------------------------------------------------------------

  describe "no_access role" do
    test "read is forbidden" do
      create_post!()
      assert {:error, _} = read_posts(%{id: 1, role: :no_access})
    end

    test "create is forbidden" do
      assert {:error, _} =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "blocked"},
                 actor: %{id: 1, role: :no_access}
               )
               |> Ash.create()
    end
  end

  # ---------------------------------------------------------------------------
  # Unconditional access — FilterBuilder returns {:ok, :unconditional}
  # Authorizer returns {:authorized, state} — no DB filter added
  # ---------------------------------------------------------------------------

  describe "admin role — unconditional" do
    test "reads all posts regardless of ownership or status" do
      p1 = create_post!(%{user_id: 1, published: false})
      p2 = create_post!(%{user_id: 2, published: true})
      p3 = create_post!(%{user_id: 3, score: 99})

      results = read_posts!(%{id: 99, role: :admin})
      assert ids(results) == ids([p1, p2, p3])
    end

    test "reads own posts even when they would fail a conditional rule" do
      own = create_post!(%{user_id: 1, published: false, score: -1})
      results = read_posts!(%{id: 1, role: :admin})
      assert own.id in ids(results)
    end
  end

  # ---------------------------------------------------------------------------
  # Equality filter — FilterBuilder returns {:ok, [user_id: id]}
  # Authorizer returns {:filter, state, [user_id: id]}
  # ---------------------------------------------------------------------------

  describe "owner role — equality filter" do
    test "reads only own posts" do
      own = create_post!(%{user_id: 1})
      _other = create_post!(%{user_id: 2})
      _third = create_post!(%{user_id: 3})

      results = read_posts!(%{id: 1, role: :owner})
      assert ids(results) == ids([own])
    end

    test "returns empty list when actor has no posts" do
      _other = create_post!(%{user_id: 2})
      results = read_posts!(%{id: 1, role: :owner})
      assert results == []
    end

    test "can create a post" do
      assert {:ok, post} =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "mine", user_id: 1},
                 actor: %{id: 1, role: :owner}
               )
               |> Ash.create()

      assert post.title == "mine"
    end

    test "cannot create when no create permission" do
      assert {:error, _} =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "blocked"},
                 actor: %{id: 1, role: :no_access}
               )
               |> Ash.create()
    end
  end

  # ---------------------------------------------------------------------------
  # AND conditions — FilterBuilder returns {:ok, [user_id: id, published: false]}
  # ---------------------------------------------------------------------------

  describe "strict_owner role — AND conjunction filter" do
    test "reads only own unpublished posts" do
      own_unpub = create_post!(%{user_id: 1, published: false})
      _own_pub = create_post!(%{user_id: 1, published: true})
      _other_unpub = create_post!(%{user_id: 2, published: false})

      results = read_posts!(%{id: 1, role: :strict_owner})
      assert ids(results) == ids([own_unpub])
    end

    test "returns empty when own posts are all published" do
      _own_pub = create_post!(%{user_id: 1, published: true})
      results = read_posts!(%{id: 1, role: :strict_owner})
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # OR conditions — FilterBuilder returns {:ok, [or: [[user_id: id], [published: true]]]}
  # ---------------------------------------------------------------------------

  describe "editor role — OR disjunction filter" do
    test "reads own posts and any published post, excluding other users' unpublished" do
      own_unpub = create_post!(%{user_id: 1, published: false})
      own_pub = create_post!(%{user_id: 1, published: true})
      other_pub = create_post!(%{user_id: 2, published: true})
      _other_unpub = create_post!(%{user_id: 2, published: false})

      results = read_posts!(%{id: 1, role: :editor})
      assert ids(results) == ids([own_unpub, own_pub, other_pub])
    end

    test "a published post owned by someone else is still readable" do
      other_pub = create_post!(%{user_id: 2, published: true})
      results = read_posts!(%{id: 1, role: :editor})
      assert other_pub.id in ids(results)
    end
  end

  # ---------------------------------------------------------------------------
  # Comparison operators — all translated to DB-level Ash filter predicates
  # ---------------------------------------------------------------------------

  describe "comparison operators" do
    test "gt — reads posts with score > 5" do
      _low = create_post!(%{score: 3})
      _boundary = create_post!(%{score: 5})
      high = create_post!(%{score: 6})
      higher = create_post!(%{score: 100})

      results = read_posts!(%{role: :score_checker})
      assert ids(results) == ids([high, higher])
    end

    test "lt — reads posts with score < 3" do
      low = create_post!(%{score: 0})
      also_low = create_post!(%{score: 2})
      _boundary = create_post!(%{score: 3})
      _high = create_post!(%{score: 10})

      results = read_posts!(%{role: :low_scorer})
      assert ids(results) == ids([low, also_low])
    end

    test "neq — reads posts where score != 0" do
      _zero = create_post!(%{score: 0})
      nonzero1 = create_post!(%{score: 1})
      nonzero2 = create_post!(%{score: -1})

      results = read_posts!(%{role: :nonzero_checker})
      assert ids(results) == ids([nonzero1, nonzero2])
    end

    test "in — reads posts whose score is in the allowed set" do
      p1 = create_post!(%{score: 1})
      _p2 = create_post!(%{score: 2})
      p3 = create_post!(%{score: 3})
      _p4 = create_post!(%{score: 4})
      p5 = create_post!(%{score: 5})

      results = read_posts!(%{role: :in_checker})
      assert ids(results) == ids([p1, p3, p5])
    end
  end

  # ---------------------------------------------------------------------------
  # Untranslatable operator (:like) — FilterBuilder returns {:error, :untranslatable}
  # Authorizer returns {:continue, state} — records fetched then filtered in check/2
  # ---------------------------------------------------------------------------

  describe "like operator — per-record fallback via check/2" do
    test "reads posts whose title matches the pattern" do
      _plain = create_post!(%{title: "hello world"})
      special = create_post!(%{title: "something special"})
      also_special = create_post!(%{title: "very special post"})

      results = read_posts!(%{role: :like_user})
      assert ids(results) == ids([special, also_special])
    end

    test "returns empty when no titles match" do
      _plain = create_post!(%{title: "hello world"})
      results = read_posts!(%{role: :like_user})
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # Function condition (:function_2) — untranslatable, falls back to check/2
  # ---------------------------------------------------------------------------

  describe "function condition — per-record fallback via check/2" do
    test "reads only own posts despite function condition being evaluated per-record" do
      own = create_post!(%{user_id: 1})
      _other = create_post!(%{user_id: 2})

      results = read_posts!(%{id: 1, role: :function_user})
      assert ids(results) == ids([own])
    end

    test "returns empty when actor owns no posts" do
      _other = create_post!(%{user_id: 2})
      results = read_posts!(%{id: 1, role: :function_user})
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # Update action — uses check/2 to validate the record being mutated
  # ---------------------------------------------------------------------------

  describe "update action" do
    test "owner can update their own post" do
      post = create_post!(%{user_id: 1})

      assert {:ok, updated} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "updated"},
                 actor: %{id: 1, role: :owner}
               )
               |> Ash.update()

      assert updated.title == "updated"
    end

    test "owner cannot update another user's post" do
      post = create_post!(%{user_id: 2})

      assert {:error, _} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "hijacked"},
                 actor: %{id: 1, role: :owner}
               )
               |> Ash.update()
    end

    test "no_access role cannot update any post" do
      post = create_post!(%{user_id: 1})

      assert {:error, _} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "blocked"},
                 actor: %{id: 1, role: :no_access}
               )
               |> Ash.update()
    end
  end
end
