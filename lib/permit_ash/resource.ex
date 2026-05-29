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

          for_actor %User{role: :admin} do
            all()
          end

          for_actor %User{id: user_id} do
            read()
            update(user_id: user_id)
          end
        end
      end

  ## `map_action`

  When an Ash action name differs from the Permit action name you want to
  authorize against, `map_action` declares the per-resource resolution. The
  authorizer substitutes the mapped Permit action name before performing
  any authorization checks.

  ## `for_actor`

  Declares authorization rules for a specific actor pattern. The pattern is
  matched at runtime, and the block specifies which actions are permitted.

  Use the helper macros `read/0,1`, `create/0,1`, `update/0,1`, `destroy/0,1`,
  and `all/0,1` inside the block. Each accepts an optional keyword list of
  conditions.

  Use `Permit.Ash.DomainPermissions` to aggregate rules from all resources in
  a domain into a `Permit.Permissions`-compatible `can/1` callback.
  """

  @action_entity %Spark.Dsl.Entity{
    name: :action,
    describe: "Grants permission for a specific action inside a for_actor block.",
    args: [:action_name, :conditions],
    target: Permit.Ash.Resource.ActionRule,
    schema: [
      action_name: [
        type: :atom,
        required: true,
        doc: "The action to permit. Use :all to permit every action."
      ],
      conditions: [
        type: :quoted,
        required: true,
        doc: "Keyword-list conditions, e.g. [user_id: user_id]. Pass [] for unconditional."
      ]
    ]
  }

  @for_actor_entity %Spark.Dsl.Entity{
    name: :for_actor,
    describe: "Declares authorization rules for actors matching the given pattern.",
    args: [:pattern],
    target: Permit.Ash.Resource.ActorRule,
    entities: [rules: [@action_entity]],
    imports: [Permit.Ash.Resource.ActionDSL],
    schema: [
      pattern: [
        type: :quoted,
        required: true,
        doc: "A pattern (struct, map, or literal) that the actor must match."
      ]
    ]
  }

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
    entities: [@map_action, @for_actor_entity]
  }

  use Spark.Dsl.Extension,
    sections: [@permit],
    transformers: [Permit.Ash.Resource.Transformer]
end
