defmodule Permit.Ash.Test.User do
  @moduledoc false
  # Plain struct — actors do not need to be Ash resources.
  defstruct [:id, :role]
end
