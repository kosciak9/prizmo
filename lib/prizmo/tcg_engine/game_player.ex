defmodule Prizmo.TcgEngine.GamePlayer do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tcg_engine_game_players"
    repo Prizmo.Repo
  end

  code_interface do
    define :create
    define :read
    define :mark_energy_attached
    define :mark_supporter_played
    define :mark_ace_spec_played
    define :mark_retreated
    define :reset_turn_flags
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:game_id, :player_id, :deck_key]
    end

    update :mark_energy_attached do
      change set_attribute(:energy_attached_this_turn?, true)
    end

    update :mark_supporter_played do
      change set_attribute(:supporter_played_this_turn?, true)
    end

    update :mark_ace_spec_played do
      change set_attribute(:ace_spec_played_this_game?, true)
    end

    update :mark_retreated do
      change set_attribute(:retreated_this_turn?, true)
    end

    update :reset_turn_flags do
      change set_attribute(:energy_attached_this_turn?, false)
      change set_attribute(:supporter_played_this_turn?, false)
      change set_attribute(:retreated_this_turn?, false)
    end

    update :restore do
      accept [
        :energy_attached_this_turn?,
        :supporter_played_this_turn?,
        :retreated_this_turn?,
        :ace_spec_played_this_game?
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :game_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :deck_key, :string do
      allow_nil? false
      public? true
    end

    attribute :energy_attached_this_turn?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :supporter_played_this_turn?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :retreated_this_turn?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :ace_spec_played_this_game?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game, Prizmo.TcgEngine.Game do
      source_attribute :game_id
      allow_nil? false
    end

    has_many :cards, Prizmo.TcgEngine.CardInstance do
      destination_attribute :game_player_id
    end
  end

  identities do
    identity :unique_game_player, [:game_id, :player_id]
  end
end
