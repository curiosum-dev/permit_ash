defmodule Permit.Ash.Actions do
  @moduledoc """
  A `Permit.Actions` implementation that derives its grouping schema from an
  Ash domain at compile time.

  All action names defined across the domain's resources become standalone
  Permit action names with no hierarchy — every action must be granted
  explicitly in the permissions module. This is the recommended approach
  for new projects using Permit with Ash.

  ## Usage

  Declare the custom action on the Ash resource as usual:

      defmodule MyApp.Post do
        use Ash.Resource,
          domain: MyApp.Domain,
          authorizers: [Permit.Ash.Authorizer],
          extensions: [Permit.Ash.Resource]

        actions do
          defaults [:read, :destroy, :create, :update]

          update :archive do
            accept []
            change set_attribute(:archived, true)
          end
        end
      end

  Point `Permit.Ash.Actions` at the domain — it collects every action name,
  including `:archive`, at compile time:

      defmodule MyApp.AshActions do
        use Permit.Ash.Actions, domain: MyApp.Domain
      end

  Use the generated action helper in the permissions module just like any
  other Permit action:

      defmodule MyApp.Permissions do
        use Permit.Permissions, actions_module: MyApp.AshActions

        def can(%User{role: :admin}) do
          permit()
          |> all(Post)
        end

        def can(%User{id: user_id}) do
          permit()
          |> read(Post)
          |> archive(Post, user_id: user_id)
        end

        def can(_), do: permit()
      end

  Because `grouping_schema/0` is called at compile time when the permissions
  module is compiled, the domain must be fully compiled before the actions
  module that references it.
  """

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)

    quote do
      use Permit.Actions

      @impl Permit.Actions
      def grouping_schema do
        Permit.Ash.Actions.derive_grouping_schema(unquote(domain))
      end
    end
  end

  @doc false
  def derive_grouping_schema(domain) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.flat_map(fn resource ->
      resource
      |> Ash.Resource.Info.actions()
      |> Enum.map(& &1.name)
    end)
    |> Enum.uniq()
    |> Map.new(&{&1, []})
  end
end
