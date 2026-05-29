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

  alias Ash.Domain.Info
  alias Permit.Actions
  alias Permit.Ash.DomainPermissions
  alias Permit.Permissions
  alias Permit.Permissions.ConditionParser

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)
    actions_module = Keyword.fetch!(opts, :actions_module)

    quote do
      use Permit.Permissions, actions_module: unquote(actions_module)

      @impl true
      def can(actor) do
        DomainPermissions.build_permissions(
          actor,
          unquote(domain),
          unquote(actions_module)
        )
      end
    end
  end

  @doc false
  def build_permissions(actor, domain, actions_module) do
    all_actions = Actions.list_groups(actions_module)

    domain
    |> Info.resources()
    |> Enum.reduce(%Permissions{}, fn resource, perms ->
      apply_resource_rules(perms, resource, actor, all_actions)
    end)
  end

  defp apply_resource_rules(perms, resource, actor, all_actions) do
    if function_exported?(resource, :__permit_rules__, 1) do
      resource.__permit_rules__(actor)
      |> Enum.reduce(perms, fn rule, perms ->
        apply_rule(perms, rule, resource, all_actions)
      end)
    else
      perms
    end
  end

  defp apply_rule(perms, {action_name, conditions}, resource, all_actions) do
    # An empty conditions list means unconditional access; Permit represents
    # this with `true` (the always-satisfied parsed condition sentinel).
    conditions_arg = if conditions == [], do: true, else: conditions

    action_name
    |> expand_action(all_actions)
    |> Enum.reduce(perms, fn action, perms ->
      Permissions.add_permission(
        perms,
        action,
        resource,
        [],
        conditions_arg,
        &ConditionParser.build/2
      )
    end)
  end

  # :all expands to every action group; any other atom stays as-is.
  defp expand_action(:all, all_actions), do: all_actions
  defp expand_action(action, _all_actions), do: [action]
end
