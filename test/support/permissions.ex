defmodule Permit.Ash.Test.Permissions do
  @moduledoc false
  use Permit.Permissions, actions_module: Permit.Actions.CrudActions

  alias Permit.Ash.Test.Post

  # Using plain map patterns avoids compile-time struct expansion dependencies.

  # Unconditional: all actions on all posts.
  def can(%{role: :admin}) do
    permit()
    |> all(Post)
  end

  # Equality filter: own posts only.
  def can(%{id: user_id, role: :owner}) do
    permit()
    |> read(Post, user_id: user_id)
    |> create(Post)
    |> update(Post, user_id: user_id)
  end

  # AND conditions: own unpublished posts only.
  def can(%{id: user_id, role: :strict_owner}) do
    permit()
    |> read(Post, user_id: user_id, published: false)
  end

  # OR conditions: own posts OR any published post.
  def can(%{id: user_id, role: :editor}) do
    permit()
    |> read(Post, user_id: user_id)
    |> read(Post, published: true)
  end

  # Comparison — gt: posts with score > 5.
  def can(%{role: :score_checker}) do
    permit()
    |> read(Post, score: {:gt, 5})
  end

  # Comparison — lt: posts with score < 3.
  def can(%{role: :low_scorer}) do
    permit()
    |> read(Post, score: {:lt, 3})
  end

  # Negation — neq: posts whose score is not 0.
  def can(%{role: :nonzero_checker}) do
    permit()
    |> read(Post, score: {:neq, 0})
  end

  # In-list operator.
  def can(%{role: :in_checker}) do
    permit()
    |> read(Post, score: {:in, [1, 3, 5]})
  end

  # Like (untranslatable) — falls back to check/2 per-record filtering.
  def can(%{role: :like_user}) do
    permit()
    |> read(Post, title: {:like, "%special%"})
  end

  # 1-arity function condition (untranslatable) — falls back to check/2.
  # Uses a 1-arity function to avoid the Permit requirement that the subject
  # be a struct when using 2-arity function conditions.
  def can(%{id: user_id, role: :function_user}) do
    permit()
    |> read(Post, fn post -> post.user_id == user_id end)
  end

  # No rules — every action is forbidden.
  def can(%{role: :no_access}), do: permit()

  def can(_), do: permit()
end
