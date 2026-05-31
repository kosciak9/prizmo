defmodule Prizmo.TcgEngine.Turn do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "tcg_engine_turns"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:status)
    initial_states([:start])
    default_initial_state(:start)

    transitions do
      transition(:draw_for_turn, from: :start, to: :drawn)
      transition(:skip_draw_for_turn, from: :start, to: :action_window)
      transition(:open_action_window, from: :drawn, to: :action_window)
      transition(:declare_attack, from: :action_window, to: :attack_declared)
      transition(:resolve_attack, from: :attack_declared, to: :attack_resolving)
      transition(:finish_attack, from: :attack_resolving, to: :ended)
      transition(:pass, from: :action_window, to: :ended)
      transition(:end_turn, from: :action_window, to: :ended)
    end
  end

  code_interface do
    define :create
    define :read
    define :draw_for_turn
    define :skip_draw_for_turn
    define :open_action_window
    define :declare_attack
    define :resolve_attack
    define :finish_attack
    define :pass
    define :end_turn
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:game_id, :turn_number, :active_player_id]
    end

    update :draw_for_turn do
      change transition_state(:drawn)
    end

    update :skip_draw_for_turn do
      change transition_state(:action_window)
    end

    update :open_action_window do
      change transition_state(:action_window)
    end

    update :declare_attack do
      accept [
        :pending_attack_id,
        :pending_attacker_card_instance_id,
        :pending_defender_card_instance_id
      ]

      change transition_state(:attack_declared)
    end

    update :resolve_attack do
      change transition_state(:attack_resolving)
    end

    update :finish_attack do
      change transition_state(:ended)
    end

    update :pass do
      change transition_state(:ended)
    end

    update :end_turn do
      change transition_state(:ended)
    end

    update :restore do
      accept [
        :status,
        :visible?,
        :pending_attack_id,
        :pending_attacker_card_instance_id,
        :pending_defender_card_instance_id
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

    attribute :turn_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :active_player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :visible?, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :pending_attack_id, :atom do
      public? true
    end

    attribute :pending_attacker_card_instance_id, :uuid do
      public? true
    end

    attribute :pending_defender_card_instance_id, :uuid do
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
    identity :unique_game_turn_number, [:game_id, :turn_number]
  end
end
