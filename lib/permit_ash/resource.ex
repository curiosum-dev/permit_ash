defmodule Permit.Ash.Resource do
  @moduledoc """
  An optional Spark DSL extension for Ash resources that provides Permit
  authorization configuration.

  ## Usage

      defmodule MyApp.Post do
        use Ash.Resource,
          authorizers: [Permit.Ash.Authorizer],
          extensions: [Permit.Ash.Resource]

        permit do
          map_action :archive, to: :update
        end
      end

  ## `map_action`

  When an Ash action name differs from the Permit action name you want to
  authorize against, `map_action` declares the per-resource resolution. The
  authorizer substitutes the mapped Permit action name before performing
  any authorization checks.

  Mappings are independent per resource — `Post` and `Comment` can map
  `:archive` to different Permit actions without conflict.

  Without any `map_action` declarations the authorizer uses the Ash action
  name directly, which is the recommended approach when using
  `Permit.Ash.Actions` as your actions module.
  """

  @map_action %Spark.Dsl.Entity{
    name: :map_action,
    describe: "Maps an Ash action name to a Permit action name for authorization.",
    args: [:action_name],
    target: Permit.Ash.Resource.ActionMapping,
    identifier: :action_name,
    schema: [
      action_name: [
        type: :atom,
        required: true,
        doc: "The Ash action name to map."
      ],
      to: [
        type: :atom,
        required: true,
        doc: "The Permit action name to resolve to during authorization."
      ]
    ]
  }

  @permit %Spark.Dsl.Section{
    name: :permit,
    describe: "Permit authorization configuration for this Ash resource.",
    entities: [@map_action]
  }

  use Spark.Dsl.Extension, sections: [@permit]
end
