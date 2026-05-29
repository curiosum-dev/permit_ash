defmodule Permit.Ash.Test.Author do
  @moduledoc false
  use Ash.Resource,
    domain: Permit.Ash.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :active, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    attribute :level, :integer do
      default(1)
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:active, :level])
    end
  end
end
