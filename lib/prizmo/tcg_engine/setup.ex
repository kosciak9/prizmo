defmodule Prizmo.TcgEngine.Setup do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "tcg_engine_setups"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:status)
    initial_states([:waiting_to_draw])
    default_initial_state(:waiting_to_draw)

    transitions do
      transition(:draw_opening_hand, from: :waiting_to_draw, to: :hands_drawn)
      transition(:place_prizes, from: :hands_drawn, to: :prizes_placed)
      transition(:complete_setup, from: :prizes_placed, to: :completed)
    end
  end

  code_interface do
    define :create
    define :read
    define :draw_opening_hand
    define :place_prizes
    define :complete_setup
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:game_id]
    end

    update :draw_opening_hand do
      change transition_state(:hands_drawn)
    end

    update :place_prizes do
      change transition_state(:prizes_placed)
    end

    update :complete_setup do
      change transition_state(:completed)
    end

    update :restore do
      accept [:status]
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

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game, Prizmo.TcgEngine.Game do
      source_attribute :game_id
      allow_nil? false
    end
  end

  identities do
    identity :unique_game_setup, [:game_id]
  end
end
