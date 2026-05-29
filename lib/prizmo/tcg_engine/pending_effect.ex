defmodule Prizmo.TcgEngine.PendingEffect do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "tcg_engine_pending_effects"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:status)
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:await_prompt, from: [:pending, :resolving], to: :awaiting_prompt)
      transition(:resume, from: :awaiting_prompt, to: :resolving)
      transition(:complete, from: [:pending, :resolving], to: :completed)
      transition(:cancel, from: [:pending, :awaiting_prompt, :resolving], to: :cancelled)
      transition(:fail, from: [:pending, :awaiting_prompt, :resolving], to: :failed)
    end
  end

  code_interface do
    define :create
    define :read
    define :await_prompt
    define :resume
    define :complete
    define :cancel
    define :fail
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :game_id,
        :source_type,
        :source_card_instance_id,
        :source_card_id,
        :controller_player_id,
        :current_player_id,
        :effect_key,
        :step,
        :state
      ]
    end

    update :await_prompt do
      accept [:current_player_id, :effect_key, :step, :state]
      change transition_state(:awaiting_prompt)
    end

    update :resume do
      accept [:current_player_id, :effect_key, :step, :state]
      change transition_state(:resolving)
    end

    update :complete do
      accept [:current_player_id, :effect_key, :step, :state]
      change transition_state(:completed)
    end

    update :cancel do
      accept [:state]
      change transition_state(:cancelled)
    end

    update :fail do
      accept [:state]
      change transition_state(:failed)
    end

    update :restore do
      accept [:status, :current_player_id, :effect_key, :step, :state]
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

    attribute :source_type, :atom do
      allow_nil? false
      public? true
    end

    attribute :source_card_instance_id, :uuid do
      public? true
    end

    attribute :source_card_id, :string do
      public? true
    end

    attribute :controller_player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :current_player_id, :string do
      public? true
    end

    attribute :effect_key, :atom do
      public? true
    end

    attribute :step, :string do
      allow_nil? false
      default "start"
      public? true
    end

    attribute :state, :map do
      allow_nil? false
      default %{}
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

    belongs_to :source_card, Prizmo.TcgEngine.CardInstance do
      source_attribute :source_card_instance_id
      allow_nil? true
    end

    has_many :prompts, Prizmo.TcgEngine.Prompt
  end
end
