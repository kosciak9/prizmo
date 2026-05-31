defmodule Prizmo.TcgEngine.Prompt do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "tcg_engine_prompts"
    repo Prizmo.Repo
  end

  state_machine do
    state_attribute(:status)
    initial_states([:awaiting_choice])
    default_initial_state(:awaiting_choice)

    transitions do
      transition(:validate_choice, from: :awaiting_choice, to: :validating)
      transition(:resolve, from: [:awaiting_choice, :validating], to: :resolved)
      transition(:cancel, from: [:awaiting_choice, :validating], to: :cancelled)
    end
  end

  code_interface do
    define :create
    define :read
    define :validate_choice
    define :resolve
    define :cancel
    define :restore
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:game_id, :turn_id, :pending_effect_id, :prompt_type, :player_id, :payload]
    end

    update :validate_choice do
      change transition_state(:validating)
    end

    update :resolve do
      accept [:payload]
      change transition_state(:resolved)
    end

    update :cancel do
      change transition_state(:cancelled)
    end

    update :restore do
      accept [:status, :payload]
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

    attribute :turn_id, :uuid do
      public? true
    end

    attribute :pending_effect_id, :uuid do
      public? true
    end

    attribute :prompt_type, :string do
      allow_nil? false
      public? true
    end

    attribute :player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
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

    belongs_to :turn, Prizmo.TcgEngine.Turn do
      source_attribute :turn_id
      allow_nil? true
    end

    belongs_to :pending_effect, Prizmo.TcgEngine.PendingEffect do
      source_attribute :pending_effect_id
      allow_nil? true
    end
  end
end
