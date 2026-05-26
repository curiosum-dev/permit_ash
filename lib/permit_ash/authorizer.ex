defmodule Permit.Ash.Authorizer do
  @behaviour Ash.Authorizer

  @impl true
  def initial_state(actor, resource, action, domain) do
    # Authorization module configured in :domain via spark dsl
    authorization_module = Permit.Ash.Domain.Info.permit_authorization_module!(domain)

    %{
      actor: actor,
      resource: resource,
      action: action,
      domain: domain,
      # Ash :actor <=> Permit :subject
      # Ash :resource <=> Permit :resource (module or struct)
      # Ash :action's :name <=> Permit :action
      permit: %{
        subject: actor,
        resource: resource,
        action: action.name,
        authorization_module: authorization_module
      }
    }
  end

  @impl true
  def strict_check_context(state) do
    # Ash will add the basics of :query and :changeset for me
    []
  end

  @impl true
  def strict_check(%{permit: permit} = state, context) do
    %{
      subject: subject,
      action: action,
      resource: resource,
      authorization_module: authorization_module
    } = permit

    case resource do
      # Asking general permission to resource module - no need to check into specific record
      module when is_atom(module) ->
        ok? =
          authorization_module.can(subject)
          |> authorization_module.do?(action, resource)

        if ok?, do: {:authorized, state}, else: {:error, :forbidden}

      # Asking permission on specific record - continue to next phase (Ash should own the
      # fetching, not Permit's and Permit.Ecto's resolvers as used by Permit.Phoenix)
      struct when is_struct(struct) ->
        {:continue, state}
    end
  end
end
