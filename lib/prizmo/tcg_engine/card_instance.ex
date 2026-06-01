defmodule Prizmo.TcgEngine.CardInstance do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  alias Prizmo.TcgEngine.CardInstance

  postgres do
    table "tcg_engine_card_instances"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:zone)
    initial_states([:deck])
    default_initial_state(:deck)

    transitions do
      transition(:draw_to_hand, from: :deck, to: :hand)
      transition(:take_prize, from: :prize, to: :hand)
      transition(:choose_active, from: :hand, to: :active)
      transition(:promote_to_active, from: :bench, to: :active)
      transition(:play_to_bench, from: :hand, to: :bench)
      transition(:move_active_to_bench, from: :active, to: :bench)
      transition(:put_basic_from_deck_to_bench, from: :deck, to: :bench)
      transition(:place_prize, from: :deck, to: :prize)
      transition(:attach, from: :hand, to: :attached)
      transition(:attach_from_deck, from: :deck, to: :attached)
      transition(:return_to_hand, from: :attached, to: :hand)
      transition(:shuffle_into_deck, from: [:attached, :discard, :hand], to: :deck)
      transition(:evolve_to_active, from: :hand, to: :active)
      transition(:evolve_to_bench, from: :hand, to: :bench)
      transition(:evolve_under, from: [:active, :bench], to: :attached)
      transition(:play_stadium, from: :hand, to: :stadium)

      transition(:discard,
        from: [:deck, :hand, :active, :bench, :attached, :stadium],
        to: :discard
      )

      transition(:recover_to_hand, from: :discard, to: :hand)
      transition(:lost_zone, from: [:hand, :active, :bench, :attached, :discard], to: :lost_zone)
    end
  end

  code_interface do
    define :create
    define :read
    define :draw_to_hand
    define :take_prize
    define :choose_active
    define :promote_to_active
    define :play_to_bench
    define :move_active_to_bench
    define :put_basic_from_deck_to_bench
    define :place_prize
    define :attach
    define :attach_from_deck
    define :return_to_hand
    define :shuffle_into_deck
    define :reorder_deck
    define :evolve_to_active
    define :evolve_to_bench
    define :evolve_under
    define :reparent_attachment
    define :play_stadium
    define :discard
    define :recover_to_hand
    define :lost_zone
    define :set_damage
    define :set_status
    define :set_markers
    define :clear_status
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :game_id,
        :game_player_id,
        :owner_player_id,
        :instance_id,
        :card_id,
        :position,
        :damage,
        :markers,
        :attached_to_card_instance_id
      ]
    end

    update :draw_to_hand do
      accept [:position]
      change transition_state(:hand)
    end

    update :take_prize do
      accept [:position]
      change transition_state(:hand)
    end

    update :choose_active do
      accept [:position, :turn_entered_play]
      change transition_state(:active)
    end

    update :promote_to_active do
      accept [:position, :status]
      change transition_state(:active)
    end

    update :play_to_bench do
      accept [:position, :turn_entered_play]
      change transition_state(:bench)
    end

    update :move_active_to_bench do
      accept [:position, :status]
      change transition_state(:bench)
    end

    update :put_basic_from_deck_to_bench do
      accept [:position, :turn_entered_play]
      change transition_state(:bench)
    end

    update :place_prize do
      accept [:position]
      change transition_state(:prize)
    end

    update :attach do
      accept [:attached_to_card_instance_id, :position]
      change transition_state(:attached)
    end

    update :attach_from_deck do
      accept [:attached_to_card_instance_id, :position]
      change transition_state(:attached)
    end

    update :return_to_hand do
      accept [:attached_to_card_instance_id, :position]
      change transition_state(:hand)
    end

    update :shuffle_into_deck do
      accept [:attached_to_card_instance_id, :position]
      change transition_state(:deck)
    end

    update :reorder_deck do
      accept [:position]
    end

    update :evolve_to_active do
      accept [:evolves_from_card_instance_id, :position, :turn_entered_play, :damage, :status]
      change transition_state(:active)
    end

    update :evolve_to_bench do
      accept [:evolves_from_card_instance_id, :position, :turn_entered_play, :damage, :status]
      change transition_state(:bench)
    end

    update :evolve_under do
      accept [:attached_to_card_instance_id, :position, :damage, :status]
      change transition_state(:attached)
    end

    update :reparent_attachment do
      accept [:attached_to_card_instance_id, :position]
    end

    update :play_stadium do
      accept [:position]
      change transition_state(:stadium)
    end

    update :discard do
      accept [
        :position,
        :damage,
        :status,
        :attached_to_card_instance_id,
        :evolves_from_card_instance_id
      ]

      change transition_state(:discard)
    end

    update :recover_to_hand do
      accept [:position]
      change transition_state(:hand)
    end

    update :lost_zone do
      accept [:position]
      change transition_state(:lost_zone)
    end

    update :set_damage do
      accept [:damage]
    end

    update :set_status do
      accept [:status]
    end

    update :set_markers do
      accept [:markers]
    end

    update :clear_status do
      change set_attribute(:status, nil)
    end

    update :restore do
      accept [
        :zone,
        :position,
        :damage,
        :status,
        :markers,
        :attached_to_card_instance_id,
        :evolves_from_card_instance_id,
        :turn_entered_play
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

    attribute :game_player_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :owner_player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :instance_id, :string do
      allow_nil? false
      public? true
    end

    attribute :card_id, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :damage, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :status, :atom do
      public? true
    end

    attribute :markers, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :attached_to_card_instance_id, :uuid do
      public? true
    end

    attribute :evolves_from_card_instance_id, :uuid do
      public? true
    end

    attribute :turn_entered_play, :integer do
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

    belongs_to :game_player, Prizmo.TcgEngine.GamePlayer do
      source_attribute :game_player_id
      allow_nil? false
    end

    belongs_to :attached_to_card, CardInstance do
      source_attribute :attached_to_card_instance_id
      allow_nil? true
    end

    belongs_to :evolves_from_card, CardInstance do
      source_attribute :evolves_from_card_instance_id
      allow_nil? true
    end
  end

  identities do
    identity :unique_game_instance, [:game_id, :instance_id]
  end
end
