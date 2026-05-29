defmodule Permit.Ash.Test.DomainPermissions do
  @moduledoc false
  use Permit.Ash.DomainPermissions,
    domain: Permit.Ash.Test.Domain,
    actions_module: Permit.Ash.Test.AshActions
end
