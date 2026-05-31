defmodule Prizmo.TcgEngine.GameSnapshot do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tcg_engine_game_snapshots"
    repo Prizmo.Repo
  end

  code_interface do
    define :create
    define :destroy
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:game_id, :game_event_id, :index, :snapshot]
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :game_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :game_event_id, :uuid do
      public? true
    end

    attribute :index, :integer do
      allow_nil? false
      public? true
    end

    attribute :snapshot, :map do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :game, Prizmo.TcgEngine.Game do
      source_attribute :game_id
      allow_nil? false
    end

    belongs_to :game_event, Prizmo.TcgEngine.GameEvent do
      source_attribute :game_event_id
      allow_nil? true
    end
  end

  identities do
    identity :unique_game_snapshot_index, [:game_id, :index]
  end
end
