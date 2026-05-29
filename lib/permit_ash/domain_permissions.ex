defmodule Permit.Ash.DomainPermissions do
  @moduledoc """
  Generates a `Permit.Permissions`-compatible module from `for_actor` rules
  declared on Ash resources in a domain.

  ## Usage

      defmodule MyApp.Permissions do
        use Permit.Ash.DomainPermissions,
          domain: MyApp.Domain,
          actions_module: MyApp.AshActions
      end

  The generated `can/1` callback iterates every resource in the domain, calls
  `resource.__permit_rules__(actor)` on each (skipping resources that don't
  implement it), and merges the resulting rules into a `%Permit.Permissions{}`
  struct.

  The `:all` sentinel action — produced by `all()` in a `for_actor` block — is
  expanded to every action group defined in the `actions_module`.

  The resulting module is a full `Permit.Permissions` module (it responds to
  `can/1`, `permit/0`, and all action-specific helpers from `actions_module`),
  so it can be used wherever `Permit.Permissions` is expected — including
  outside the Ash context via `Permit.ResolverBase`.
  """

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)
    actions_module = Keyword.fetch!(opts, :actions_module)

    quote do
      use Permit.Permissions, actions_module: unquote(actions_module)

      @impl true
      def can(actor) do
        Permit.Ash.DomainPermissions.build_permissions(
          actor,
          unquote(domain),
          unquote(actions_module)
        )
      end
    end
  end

  @doc false
  def build_permissions(actor, domain, actions_module) do
    all_actions = Permit.Actions.list_groups(actions_module)

    domain
    |> Ash.Domain.Info.resources()
    |> Enum.reduce(%Permit.Permissions{}, fn resource, perms ->
      if function_exported?(resource, :__permit_rules__, 1) do
        resource
        |> apply(:__permit_rules__, [actor])
        |> Enum.reduce(perms, fn {action_name, conditions}, perms ->
          expand_action(action_name, all_actions)
          |> Enum.reduce(perms, fn action, perms ->
            # An empty conditions list means unconditional access; Permit represents
            # this with `true` (the always-satisfied parsed condition sentinel).
            conditions_arg = if conditions == [], do: true, else: conditions

            Permit.Permissions.add_permission(
              perms,
              action,
              resource,
              [],
              conditions_arg,
              &Permit.Permissions.ConditionParser.build/2
            )
          end)
        end)
      else
        perms
      end
    end)
  end

  # :all expands to every action group; any other atom stays as-is.
  defp expand_action(:all, all_actions), do: all_actions
  defp expand_action(action, _), do: [action]
end
