defmodule Prizmo.TcgEngine.Game do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    fragments: [Prizmo.TcgEngine.Game.ActionCommands],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshTypescript.Resource]

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameView
  alias Prizmo.TcgEngine.GameView.Fields, as: GameViewFields
  alias Prizmo.TcgEngine.SupportedDecks

  @supported_deck_fields [
    deck_key: [type: :string, allow_nil?: false],
    name: [type: :string, allow_nil?: false],
    source_url: [type: :string, allow_nil?: false],
    card_count: [type: :integer, allow_nil?: false],
    unique_card_count: [type: :integer, allow_nil?: false]
  ]

  @player_deck_selection_fields [
    player_id: [type: :string, allow_nil?: false],
    deck_key: [type: :string, allow_nil?: false]
  ]

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
      transition(:choose_starting_player, from: :created, to: :setup)
      transition(:complete_setup, from: :setup, to: :in_progress)
      transition(:finish, from: [:created, :setup, :in_progress], to: :finished)
    end
  end

  typescript do
    type_name "TcgEngineGame"
  end

  code_interface do
    define :create
    define :read
    define :list_supported_decks
    define :create_from_supported_decks, args: [:players]
    define :start_setup_command, args: [:game_id]
    define :call_coin_toss_command, args: [:game_id, :player_id, :call]

    define :choose_starting_player_command,
      args: [:game_id, :chooser_player_id, :starting_player_id]

    define :draw_opening_hand_command, args: [:game_id]
    define :choose_active_from_hand_command, args: [:game_id, :player_id, :card_instance_id]
    define :choose_setup_bench_from_hand_command, args: [:game_id, :player_id, :card_instance_id]
    define :finish_setup_choices_command, args: [:game_id, :player_id]
    define :place_prizes_command, args: [:game_id]
    define :complete_setup_command, args: [:game_id]
    define :start_next_turn_command, args: [:game_id]
    define :draw_for_turn_command, args: [:game_id, :player_id]
    define :skip_draw_for_turn_command, args: [:game_id, :player_id]
    define :open_action_window_command, args: [:game_id]
    define :play_card_command, args: [:game_id, :player_id, :card_instance_id]
    define :play_basic_to_bench_command, args: [:game_id, :player_id, :card_instance_id]
    define :pass_turn_command, args: [:game_id, :player_id]
    define :undo_command, args: [:game_id]
    define :start_setup
    define :complete_setup
    define :finish
    define :set_active_player
    define :set_winner
    define :record_coin_toss
    define :choose_starting_player
    define :set_flow_state
    define :set_cursor
    define :record_event_cursor
    define :restore
  end

  actions do
    defaults [:read]

    action :list_supported_decks, {:array, :map} do
      description "List supported deck fixtures that can create TCG engine games."

      constraints items: [fields: @supported_deck_fields]

      run fn _input, _context ->
        {:ok, SupportedDecks.list()}
      end
    end

    action :create_from_supported_decks, :struct do
      description "Create a TCG engine game from supported deck fixture keys."

      constraints instance_of: Game

      argument :players, {:array, :map} do
        allow_nil? false
        constraints items: [fields: @player_deck_selection_fields]
      end

      argument :active_player_id, :string

      run fn input, _context ->
        opts =
          case Map.get(input.arguments, :active_player_id) do
            nil -> []
            active_player_id -> [active_player_id: active_player_id]
          end

        SupportedDecks.create_game(input.arguments.players, opts)
      end
    end

    action :get_state, :map do
      constraints fields: GameViewFields.game_state_fields()
      argument :game_id, :uuid, allow_nil?: false
      argument :viewer_player_id, :string, allow_nil?: false

      run fn input, _context ->
        GameView.for_player(input.arguments.game_id, input.arguments.viewer_player_id)
      end
    end

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

    update :record_coin_toss do
      accept [
        :flow_state,
        :coin_toss_calling_player_id,
        :coin_toss_call,
        :coin_toss_result,
        :coin_toss_winner_player_id
      ]
    end

    update :choose_starting_player do
      accept [
        :flow_state,
        :active_player_id,
        :first_player_id,
        :starting_player_chosen_by_player_id
      ]

      change transition_state(:setup)
    end

    update :set_flow_state do
      accept [:flow_state]
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
        :flow_state,
        :coin_toss_calling_player_id,
        :coin_toss_call,
        :coin_toss_result,
        :coin_toss_winner_player_id,
        :starting_player_chosen_by_player_id,
        :cursor_index,
        :latest_event_index
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:action) do
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

    attribute :flow_state, :atom do
      allow_nil? false
      default :pregame_awaiting_coin_toss
      public? true
    end

    attribute :coin_toss_calling_player_id, :string do
      public? true
    end

    attribute :coin_toss_call, :atom do
      public? true
    end

    attribute :coin_toss_result, :atom do
      public? true
    end

    attribute :coin_toss_winner_player_id, :string do
      public? true
    end

    attribute :starting_player_chosen_by_player_id, :string do
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
