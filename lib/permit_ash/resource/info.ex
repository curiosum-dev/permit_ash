defmodule Permit.Ash.Resource.Info do
  @moduledoc """
  Introspection helpers for the `Permit.Ash.Resource` DSL extension.

  ## Generated functions

  - `permit/1` — returns the list of all entities in the `permit` section
    (i.e. `map_action` declarations), or `[]` if none are defined or the
    extension is not loaded on the resource.
  """

  use Spark.InfoGenerator,
    extension: Permit.Ash.Resource,
    sections: [:permit]

  @doc """
  Returns `{:ok, permit_action}` if a `map_action` is declared for `action_name`
  on `resource`, or `:error` if none is defined.

  Safe to call on any Ash resource regardless of whether `Permit.Ash.Resource`
  is loaded as an extension — returns `:error` in that case.
  """
  @spec action_mapping(module(), atom()) :: {:ok, atom()} | :error
  def action_mapping(resource, action_name) do
    resource
    |> permit()
    |> Enum.filter(&match?(%Permit.Ash.Resource.ActionMapping{}, &1))
    |> Enum.find(&(&1.action_name == action_name))
    |> case do
      nil -> :error
      %{to: permit_action} -> {:ok, permit_action}
    end
  rescue
    _ -> :error
  end
end
