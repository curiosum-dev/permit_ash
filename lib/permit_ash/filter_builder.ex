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
    * Pattern/regex operators (`:like`, `:ilike`, `:match`) used inside association
      conditions — these have no Ash filter equivalent in core Ash regardless of nesting
      depth.
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

  # Association condition: translate nested keyword conditions recursively.
  # The nested values support simple equality and further nesting. Operator
  # tuples at nested levels (e.g. `author: [score: {:gt, 5}]`) are not
  # supported — Permit.Ecto does not handle them correctly either.
  defp translate_condition(
         %ParsedCondition{
           condition: {key, val_fn},
           condition_type: {:association, _},
           not: not?
         },
         subject,
         resource_module
       ) do
    nested = val_fn.(subject, resource_module)

    case translate_assoc_conditions(nested) do
      {:ok, ash_nested} ->
        filter = [{key, ash_nested}]
        {:ok, if(not?, do: [{:not, filter}], else: filter)}

      {:error, _} = error ->
        error
    end
  end

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

  # ---------------------------------------------------------------------------
  # Private: association nested condition translation
  #
  # Permit stores nested association conditions as raw keyword lists returned
  # by the condition's val_fn. Values at the leaf level may be plain scalars
  # (equality), Permit operator tuples (e.g. {:gt, 5}), or further nested
  # keyword lists (deeper association path). All operator forms supported at the
  # top level are supported here too, by routing through operator_to_filter/4
  # via raw_op_to_module/1.
  #
  # nil at leaf level is treated as IS NULL (matching Permit's top-level nil
  # handling, where ConditionParser converts nil to an IsNil operator).
  #
  # Pattern/regex operators (:like, :ilike, :match) remain untranslatable.
  # ---------------------------------------------------------------------------

  defp translate_assoc_conditions(conditions) when is_list(conditions) do
    Enum.reduce_while(conditions, {:ok, []}, fn {field, raw_value}, {:ok, acc} ->
      case translate_assoc_leaf(field, raw_value) do
        {:ok, fragment} -> {:cont, {:ok, acc ++ fragment}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # nil → IS NULL (mirrors Permit's top-level ConditionParser nil handling).
  defp translate_assoc_leaf(field, nil),
    do: {:ok, [{field, [is_nil: true]}]}

  # {:not, nil} → IS NOT NULL
  defp translate_assoc_leaf(field, {:not, nil}),
    do: {:ok, [{field, [is_nil: false]}]}

  # {:not, value} → NOT EQUAL (Permit treats {eq, value} with not: true)
  defp translate_assoc_leaf(field, {:not, value}),
    do: operator_to_filter(Permit.Operators.Eq, field, value, true)

  # {{:not, op}, value} → negated operator, e.g. {{:not, :gt}, 3} = lte: 3
  defp translate_assoc_leaf(field, {{:not, op}, value}) when is_atom(op) do
    case raw_op_to_module(op) do
      {:ok, module} -> operator_to_filter(module, field, value, true)
      error -> error
    end
  end

  # {:op, value} → operator tuple, e.g. {:gt, 5}, {:in, [1, 2, 3]}
  defp translate_assoc_leaf(field, {op, value}) when is_atom(op) do
    case raw_op_to_module(op) do
      {:ok, module} -> operator_to_filter(module, field, value, false)
      error -> error
    end
  end

  # Nested keyword list → recurse into the next level of the association path.
  defp translate_assoc_leaf(field, raw_value) when is_list(raw_value) do
    case translate_assoc_conditions(raw_value) do
      {:ok, nested} -> {:ok, [{field, nested}]}
      error -> error
    end
  end

  # Plain scalar (boolean, integer, string, atom) → simple equality.
  defp translate_assoc_leaf(field, raw_value),
    do: {:ok, [{field, raw_value}]}

  # Maps Permit's raw DSL operator atoms to Permit operator modules so that
  # operator_to_filter/4 can be reused for nested association conditions.
  defp raw_op_to_module(op) when op in [:==, :eq], do: {:ok, Permit.Operators.Eq}
  defp raw_op_to_module(op) when op in [:!=, :neq], do: {:ok, Permit.Operators.Neq}
  defp raw_op_to_module(op) when op in [:>, :gt], do: {:ok, Permit.Operators.Gt}
  defp raw_op_to_module(op) when op in [:<, :lt], do: {:ok, Permit.Operators.Lt}
  defp raw_op_to_module(op) when op in [:>=, :ge], do: {:ok, Permit.Operators.Ge}
  defp raw_op_to_module(op) when op in [:<=, :le], do: {:ok, Permit.Operators.Le}
  defp raw_op_to_module(op) when op in [:is_nil, :nil?], do: {:ok, Permit.Operators.IsNil}
  defp raw_op_to_module(:in), do: {:ok, Permit.Operators.In}
  defp raw_op_to_module(_), do: {:error, :untranslatable}
end
