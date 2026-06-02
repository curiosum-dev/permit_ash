defmodule Permit.Ash.Resource.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Permit.Ash.Resource.ActorRule
  alias Spark.Dsl.Transformer

  @doc false
  def transform(dsl_state) do
    # Read ActorRule data (the actor's pattern expression and rules) from parsed
    # DSL state in the `permit do ... end` block
    for_actor_entities =
      dsl_state
      |> Transformer.get_entities([:permit])
      |> Enum.filter(&match?(%ActorRule{}, &1))

    # Build one function clause per for_actor block, then the catchall (for when the
    # actor doesn't match any for_actor pattern).
    clauses =
      for_actor_entities
      |> Enum.map(&build_clause/1)
      |> Kernel.++([
        quote do
          def __permit_rules__(_), do: []
        end
      ])

    combined =
      Enum.reduce(clauses, nil, fn clause, acc ->
        if acc do
          quote do
            unquote(acc)
            unquote(clause)
          end
        else
          clause
        end
      end) ||
        quote do
          def __permit_rules__(_), do: []
        end

    # Inject the combination of clauses of the `__permit_rules__` function into our
    # Ash resource module.
    {:ok, Transformer.eval(dsl_state, [], combined)}
  end

  # Build a single `def __permit_rules__(pattern) do rules end` clause.
  defp build_clause(%ActorRule{pattern: pattern_ast, rules: rules}) do
    rules_ast = Enum.map(rules, &rule_to_ast/1)

    quote do
      def __permit_rules__(unquote(pattern_ast)) do
        unquote(rules_ast)
      end
    end
  end

  # Convert an ActionRule struct to a 2-tuple AST: {action_name, conditions_ast}.
  defp rule_to_ast(%Permit.Ash.Resource.ActionRule{action_name: action, conditions: conds}) do
    # conds is already the AST of the conditions expression (stored via :quoted type).
    # Build the tuple literal {action, conditions} as an AST node.
    {:{}, [], [action, conds]}
  end
end
