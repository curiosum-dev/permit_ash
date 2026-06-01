defmodule Permit.Ash.Test.Post do
  @moduledoc false
  use Ash.Resource,
    domain: Permit.Ash.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Permit.Ash.Authorizer],
    extensions: [Permit.Ash.Resource]

  ets do
    # Private tables are scoped to the owning process, giving each test process
    # its own isolated data store.
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      default("untitled")
      public?(true)
    end

    attribute :user_id, :integer do
      allow_nil?(true)
      public?(true)
    end

    attribute :published, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :score, :integer do
      default(0)
      public?(true)
    end
  end

  relationships do
    belongs_to :author, Permit.Ash.Test.Author do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end
  end

  permit do
    map_action(:publish, to: :update)

    # for_actor rules used by DomainPermissions tests.
    for_actor %{role: :admin} do
      action(:all)
    end

    for_actor %{id: user_id, role: :owner} do
      action(:read)
      action(:create)
      action(:update, user_id: user_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :user_id, :published, :score, :author_id])
    end

    update :update do
      accept([:title, :published, :score])
    end

    # Custom update action used to test map_action resolution: :publish maps
    # to the Permit :update action, so update permissions cover it.
    update :publish do
      accept [:published]
    end
  end
end
