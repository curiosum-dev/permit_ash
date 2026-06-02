defmodule Permit.Ash.Authorizer do
  @moduledoc false
  @behaviour Ash.Authorizer

  alias Ash.Error.Forbidden
  alias Permit.Ash.Domain.Info, as: DomainInfo
  alias Permit.Ash.FilterBuilder

  # Ash.Authorizer types the `resource` argument of initial_state/4 as
  # Ash.Resource.Record.t() (= struct()), but Ash actually passes the resource
  # MODULE (an atom) at runtime. Suppress the false-positive callback mismatch.
  @dialyzer {:nowarn_function, initial_state: 4}

  @impl true
  def initial_state(actor, resource, action, domain) do
    # Authorization module configured in :domain via spark dsl
    authorization_module = DomainInfo.permit_authorization_module!(domain)

    %{
      actor: actor,
      resource: resource,
      action: action,
      domain: domain,
      # Ash :actor <=> Permit :subject
      # Ash :resource <=> Permit :resource (module or struct)
      # Ash :action's :name <=> Permit :action (resolved via map_action if declared)
      permit: %{
        subject: actor,
        resource: resource,
        action: resolve_permit_action(resource, action),
        authorization_module: authorization_module
      }
    }
  end

  # Resolves the Permit action atom for a given Ash action.
  # Checks for an explicit map_action declaration on the resource first;
  # falls back to the Ash action name directly if none is found.
  defp resolve_permit_action(resource, action) do
    case Permit.Ash.Resource.Info.action_mapping(resource, action.name) do
      {:ok, permit_action} -> permit_action
      :error -> action.name
    end
  end

  @impl true
  def strict_check_context(_state), do: []

  # Called by Ash when check/2 returns {:error, :forbidden, state} or when
  # {:continue, state} is returned but Ash cannot run the check phase
  # (no_check?: true). Returning Ash.Error.Forbidden ensures Ash classifies
  # the result correctly rather than wrapping it as Ash.Error.Unknown.
  @impl true
  def exception(_reason, _state), do: Forbidden.exception([])

  # Anonymous actors can never be authorized.
  @impl true
  def strict_check(%{permit: %{subject: nil}} = _state, _context) do
    {:error, Forbidden.exception([])}
  end

  # For updates and destroys the record being mutated is available in
  # context[:changeset].data. Do the per-record Permit check right here so
  # Ash's atomic update path (which requires a definitive strict_check answer
  # and passes no_check?: true) gets a clear authorized/forbidden decision
  # without needing to fall through to check/2.
  def strict_check(
        %{
          action: %{type: type},
          permit: %{
            subject: subject,
            action: action,
            authorization_module: auth_module
          }
        } = state,
        %{changeset: %Ash.Changeset{data: record}}
      )
      when type in [:update, :destroy] and not is_nil(record) do
    if Permit.ResolverBase.authorized?(subject, auth_module, record, action) do
      {:authorized, state}
    else
      {:error, :forbidden}
    end
  end

  # For reads: translate Permit rules to DB-level Ash filter expressions where
  # possible, falling back to check/2 per-record filtering for untranslatable
  # conditions (function conditions, :like, :ilike, :match).
  #
  # For creates: fall through to the filter/continue logic below; creates are
  # handled by the filter path (Ash stashes filters for post-creation checks)
  # or by check/2 (via {:continue, state}).
  def strict_check(
        %{
          permit: %{
            subject: subject,
            action: action,
            resource: resource,
            authorization_module: auth_module
          }
        } = state,
        _context
      ) do
    permissions = auth_module.can(subject).permissions
    dnf = Map.get(permissions.conditions_map, {action, resource})

    case FilterBuilder.build(dnf, subject, resource) do
      {:ok, :unconditional} ->
        # At least one rule branch is unconditional: every record passes.
        {:authorized, state}

      {:ok, keyword_filter} when action == :read ->
        # All conditions are translatable: push the filter to the DB query.
        # Tuple order confirmed from Ash.Policy.Authorizer and can.ex:
        # {:filter, state, filter}.
        {:filter, state, keyword_filter}

      {:ok, _keyword_filter} ->
        # Non-read action with translatable conditions: let check/2 handle it.
        # (For writes, Ash stores inspect(authorizer) as a string in the
        # filter error placeholder, causing a crash on the forbidden path.)
        {:continue, state}

      {:error, :untranslatable} ->
        # A condition requires runtime evaluation (function condition or
        # unsupported operator like :like). Ash fetches records and check/2
        # filters them in-process.
        {:continue, state}

      {:error, :no_rules} ->
        # No direct DNF entry for {action, resource_module}. Can happen when
        # the permission was granted via an action group (e.g. :manage implies
        # :create). Fall back to Permit's transitive authorized? check; if
        # authorized, check/2 handles per-record filtering.
        if Permit.ResolverBase.authorized?(subject, auth_module, resource, action) do
          {:continue, state}
        else
          {:error, Forbidden.exception([])}
        end
    end
  end

  @impl true
  def check_context(_state), do: []

  @impl true
  def check(
        %{
          permit: %{
            subject: subject,
            action: action,
            authorization_module: auth_module
          }
        } = _state,
        context
      ) do
    records = context[:data] || []

    authorized =
      Enum.filter(records, fn record ->
        Permit.ResolverBase.authorized?(subject, auth_module, record, action)
      end)

    {:data, authorized}
  end
end
