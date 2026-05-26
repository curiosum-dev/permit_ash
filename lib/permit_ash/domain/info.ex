defmodule Permit.Ash.Domain.Info do
  @moduledoc """
  Introspection helpers for the `Permit.Ash.Domain` extension.

  ## Generated functions

  - `permit_authorization_module/1` — returns `{:ok, module} | :error`
  - `permit_authorization_module!/1` — returns `module` or raises if not configured
  """

  use Spark.InfoGenerator,
    extension: Permit.Ash.Domain,
    sections: [:permit]
end
