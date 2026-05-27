defmodule Permit.Ash.FilterBuilder do
  @moduledoc """
  Translates a Permit `DisjunctiveNormalForm` into an Ash filter keyword list.

  Permit stores authorization rules as a DNF (disjunction of conjunctions). This module
  walks that tree and converts each operator-based condition into the equivalent Ash filter
  keyword syntax, enabling DB-level filtering via `strict_check/2`'s `{:filter, state, kw}`
  return path.

  ## Return values of `build/3`

    * `{:ok, :unconditional}` — at least one rule branch is unconditional; all records pass.
      The caller should return `{:authorized, state}`.

    * `{:ok, keyword_list}` — all conditions translated successfully; apply as a DB filter.
      The caller should return `{:filter, state, keyword_list}`.

    * `{:error, :no_rules}` — no DNF entry exists for this action/resource pair in the
      conditions map. The caller should fall back via `Permit.ResolverBase.authorized?/4`
      to distinguish forbidden from a group-transitive permission.

    * `{:error, :untranslatable}` — at least one condition uses a runtime function or an
      operator with no Ash filter equivalent (`:like`, `:ilike`, `:match`). The caller
      should return `{:continue, state}` and rely on `check/2` for per-record filtering.

  ## Unsupported conditions (fall back to `check/2`)

    * Function conditions (`:function_1`, `:function_2`) — arbitrary Elixir functions cannot
      be expressed as SQL predicates.
    * Association conditions (`{:association, _}`) — require JOIN semantics that depend on
      Ash relationship metadata; not yet implemented.
    * `:like`, `:ilike`, `:match` — no direct Ash filter operator equivalents in core Ash.
  """

  alias Permit.Permissions.DisjunctiveNormalForm
  alias Permit.Permissions.ParsedConditionList
  alias Permit.Permissions.ParsedCondition

  @doc """
  Builds an Ash filter keyword list from a Permit `DisjunctiveNormalForm`.

  `subject` and `resource_module` are passed to any value-binding functions embedded in
  conditions (e.g. `author_id: user.id` closes over `user` but the closure still receives
  the subject and resource at resolution time).
  """
  @spec build(DisjunctiveNormalForm.t() | nil, term(), module()) ::
          {:ok, :unconditional}
          | {:ok, keyword()}
          | {:error, :no_rules}
          | {:error, :untranslatable}
  def build(nil, _subject, _resource_module), do: {:error, :no_rules}

  def build(%DisjunctiveNormalForm{disjunctions: []}, _subject, _resource_module),
    do: {:error, :no_rules}

  def build(%DisjunctiveNormalForm{disjunctions: disjunctions}, subject, resource_module) do
    disjunctions
    |> Enum.reduce_while({:ok, []}, fn conjunction, {:ok, branches} ->
      case translate_conjunction(conjunction, subject, resource_module) do
        :unconditional ->
          # One branch with no conditions means every record passes; short-circuit.
          {:halt, {:ok, :unconditional}}

        :impossible ->
          # This branch always fails (a `const: false` condition); skip it.
          {:cont, {:ok, branches}}

        {:ok, fragment} ->
          {:cont, {:ok, [fragment | branches]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, :unconditional} -> {:ok, :unconditional}
      {:ok, []} -> {:error, :no_rules}
      {:ok, [single]} -> {:ok, single}
      {:ok, many} -> {:ok, [or: many]}
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Private: conjunction (AND of conditions)
  # ---------------------------------------------------------------------------

  # Returns: :unconditional | :impossible | {:ok, keyword()} | {:error, :untranslatable}
  defp translate_conjunction(%ParsedConditionList{conditions: conditions}, subject, resource_module) do
    conditions
    |> Enum.reduce_while({:ok, []}, fn condition, {:ok, predicates} ->
      case translate_condition(condition, subject, resource_module) do
        :skip ->
          {:cont, {:ok, predicates}}

        :impossible ->
          {:halt, :impossible}

        {:ok, fragment} ->
          {:cont, {:ok, fragment ++ predicates}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      :impossible -> :impossible
      {:ok, []} -> :unconditional
      {:ok, predicates} -> {:ok, predicates}
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Private: individual condition
  # ---------------------------------------------------------------------------

  # A `true` const means "no condition"; skip it — it does not constrain the conjunction.
  defp translate_condition(
         %ParsedCondition{condition_type: :const, condition: true},
         _subject,
         _resource_module
       ),
       do: :skip

  # A `false` const makes the entire conjunction impossible.
  defp translate_condition(
         %ParsedCondition{condition_type: :const, condition: false},
         _subject,
         _resource_module
       ),
       do: :impossible

  # Operator-based condition: resolve the value and map to an Ash filter fragment.
  defp translate_condition(
         %ParsedCondition{
           condition: {key, val_fn},
           condition_type: {:operator, operator_module},
           not: not?
         },
         subject,
         resource_module
       ) do
    value = val_fn.(subject, resource_module)
    operator_to_filter(operator_module, key, value, not?)
  end

  # Association, function, and unknown conditions cannot be pushed to the DB.
  defp translate_condition(%ParsedCondition{condition_type: {:association, _}}, _, _),
    do: {:error, :untranslatable}

  defp translate_condition(%ParsedCondition{condition_type: :function_1}, _, _),
    do: {:error, :untranslatable}

  defp translate_condition(%ParsedCondition{condition_type: :function_2}, _, _),
    do: {:error, :untranslatable}

  # ---------------------------------------------------------------------------
  # Private: Permit operator → Ash filter keyword fragment
  #
  # Each clause returns `{:ok, keyword()}` — a list of one or more key-value pairs
  # that can be concatenated into a conjunction keyword list by the caller.
  #
  # Negation of comparison operators is simplified algebraically rather than
  # wrapping in `[not: ...]`, keeping the resulting SQL predicates as direct
  # comparisons where possible.
  # ---------------------------------------------------------------------------

  defp operator_to_filter(Permit.Operators.Eq, key, value, false),
    do: {:ok, [{key, value}]}

  # Eq + not → use not_eq instead of wrapping in NOT
  defp operator_to_filter(Permit.Operators.Eq, key, value, true),
    do: {:ok, [{key, [not_eq: value]}]}

  defp operator_to_filter(Permit.Operators.Neq, key, value, false),
    do: {:ok, [{key, [not_eq: value]}]}

  # Neq + not → double negation = equality
  defp operator_to_filter(Permit.Operators.Neq, key, value, true),
    do: {:ok, [{key, value}]}

  defp operator_to_filter(Permit.Operators.Gt, key, value, false),
    do: {:ok, [{key, [gt: value]}]}

  # NOT (field > value) = field <= value
  defp operator_to_filter(Permit.Operators.Gt, key, value, true),
    do: {:ok, [{key, [lte: value]}]}

  defp operator_to_filter(Permit.Operators.Lt, key, value, false),
    do: {:ok, [{key, [lt: value]}]}

  # NOT (field < value) = field >= value
  defp operator_to_filter(Permit.Operators.Lt, key, value, true),
    do: {:ok, [{key, [gte: value]}]}

  defp operator_to_filter(Permit.Operators.Ge, key, value, false),
    do: {:ok, [{key, [gte: value]}]}

  # NOT (field >= value) = field < value
  defp operator_to_filter(Permit.Operators.Ge, key, value, true),
    do: {:ok, [{key, [lt: value]}]}

  defp operator_to_filter(Permit.Operators.Le, key, value, false),
    do: {:ok, [{key, [lte: value]}]}

  # NOT (field <= value) = field > value
  defp operator_to_filter(Permit.Operators.Le, key, value, true),
    do: {:ok, [{key, [gt: value]}]}

  # IsNil: the `not` flag flips the boolean expectation rather than wrapping.
  defp operator_to_filter(Permit.Operators.IsNil, key, _value, not?),
    do: {:ok, [{key, [is_nil: !not?]}]}

  defp operator_to_filter(Permit.Operators.In, key, value, false),
    do: {:ok, [{key, [in: value]}]}

  # NOT IN requires a [not: ...] wrapper since Ash has no `not_in` operator.
  defp operator_to_filter(Permit.Operators.In, key, value, true),
    do: {:ok, [{:not, [{key, [in: value]}]}]}

  # No direct Ash filter equivalents for pattern/regex operators.
  defp operator_to_filter(Permit.Operators.Like, _, _, _), do: {:error, :untranslatable}
  defp operator_to_filter(Permit.Operators.Ilike, _, _, _), do: {:error, :untranslatable}
  defp operator_to_filter(Permit.Operators.Match, _, _, _), do: {:error, :untranslatable}

  defp operator_to_filter(_unknown, _, _, _), do: {:error, :untranslatable}
end
