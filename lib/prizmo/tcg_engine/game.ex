defmodule Prizmo.TcgEngine.Game do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "tcg_engine_games"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:status)
    initial_states([:created])
    default_initial_state(:created)

    transitions do
      transition(:start_setup, from: :created, to: :setup)
      transition(:complete_setup, from: :setup, to: :in_progress)
      transition(:finish, from: [:created, :setup, :in_progress], to: :finished)
    end
  end

  code_interface do
    define :create
    define :read
    define :start_setup
    define :complete_setup
    define :finish
    define :set_active_player
    define :set_winner
    define :set_cursor
    define :record_event_cursor
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:active_player_id, :first_player_id, :cursor_index, :latest_event_index]
    end

    update :start_setup do
      change transition_state(:setup)
    end

    update :complete_setup do
      change transition_state(:in_progress)
    end

    update :finish do
      accept [:winner_player_id]
      change transition_state(:finished)
    end

    update :set_active_player do
      accept [:active_player_id]
    end

    update :set_winner do
      accept [:winner_player_id]
    end

    update :set_cursor do
      accept [:cursor_index]
    end

    update :record_event_cursor do
      accept [:cursor_index, :latest_event_index]
    end

    update :restore do
      accept [
        :status,
        :active_player_id,
        :first_player_id,
        :winner_player_id,
        :cursor_index,
        :latest_event_index
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

    attribute :active_player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :first_player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :winner_player_id, :string do
      public? true
    end

    attribute :cursor_index, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :latest_event_index, :integer do
      allow_nil? false
      default 0
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :players, Prizmo.TcgEngine.GamePlayer
    has_many :turns, Prizmo.TcgEngine.Turn
    has_many :cards, Prizmo.TcgEngine.CardInstance
    has_many :events, Prizmo.TcgEngine.GameEvent
    has_many :snapshots, Prizmo.TcgEngine.GameSnapshot
    has_many :prompts, Prizmo.TcgEngine.Prompt
    has_one :setup, Prizmo.TcgEngine.Setup
  end
end
