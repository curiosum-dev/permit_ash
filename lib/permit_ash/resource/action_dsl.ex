defmodule Permit.Ash.Resource.ActionDSL do
  @moduledoc false
  # Helper macros imported into the `for_actor` block scope.
  # Each macro expands to an `action` nested entity call with two positional args
  # (action_name and conditions). Both args are required by the entity schema and
  # go through Spark's escape_quoted path, which properly handles :quoted type so
  # variable references from the for_actor pattern remain as AST rather than being
  # evaluated in the module body scope.

  defmacro read(conditions \\ []) do
    quote do: action(:read, unquote(conditions))
  end

  defmacro create(conditions \\ []) do
    quote do: action(:create, unquote(conditions))
  end

  defmacro update(conditions \\ []) do
    quote do: action(:update, unquote(conditions))
  end

  defmacro destroy(conditions \\ []) do
    quote do: action(:destroy, unquote(conditions))
  end

  # :all is a sentinel — DomainPermissions expands it to every action group.
  defmacro all(conditions \\ []) do
    quote do: action(:all, unquote(conditions))
  end
end
