defmodule Permit.Ash.Domain do
  @moduledoc """
  A Spark DSL extension for Ash Domains that configures Permit.Ash authorization.

  ## Usage

      defmodule MyApp.Blog do
        use Ash.Domain, extensions: [Permit.Ash.Domain]

        permit do
          authorization_module MyApp.Authorization
        end
      end

  The `authorization_module` must be a module that `use Permit`.
  """

  @permit %Spark.Dsl.Section{
    name: :permit,
    describe: "Configuration for Permit.Ash authorization.",
    no_depend_modules: [:authorization_module],
    schema: [
      authorization_module: [
        type: :atom,
        required: true,
        doc: """
        The module that mixes in `use Permit` or `use Permit.Ecto` and defines
        authorization rules for this domain.
        """
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@permit]
end
