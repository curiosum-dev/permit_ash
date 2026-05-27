defmodule Permit.Ash.Test.Domain do
  @moduledoc false
  # validate_config_inclusion?: false breaks the compile-time cycle between the
  # domain (which references Post) and Post (which references this domain).
  use Ash.Domain, extensions: [Permit.Ash.Domain], validate_config_inclusion?: false

  permit do
    authorization_module Permit.Ash.Test.Authorization
  end

  resources do
    resource Permit.Ash.Test.Post
    resource Permit.Ash.Test.Author
  end
end
