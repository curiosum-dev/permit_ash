defmodule Permit.Ash.Test.PostActorFirst do
  @moduledoc false
  # Minimal resource used to test that map_action works regardless of
  # whether it's before or after for_actor
  use Ash.Resource,
    domain: Permit.Ash.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Permit.Ash.Authorizer],
    extensions: [Permit.Ash.Resource]

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
  end

  permit do
    for_actor %{role: :admin} do
      action(:all)
    end

    map_action(:publish, to: :update)
  end

  actions do
    defaults([:read])

    update :update do
      accept([])
    end

    update :publish do
      accept([])
    end
  end
end
