defmodule Prizmo.TcgEngine.Game do
  @moduledoc false

  use Ash.Resource,
    otp_app: :prizmo,
    domain: Prizmo.TcgEngine,
    fragments: [Prizmo.TcgEngine.Game.ActionCommands, Prizmo.TcgEngine.Game.SupportedDeckActions],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshTypescript.Resource]

  alias Prizmo.TcgEngine.Decklists
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameView
  alias Prizmo.TcgEngine.GameView.Fields, as: GameViewFields
  alias Prizmo.TcgEngine.SupportedDecks

  @player_deck_selection_fields [
    player_id: [type: :string, allow_nil?: false],
    deck_key: [type: :string, allow_nil?: false]
  ]

  @open_deck_card_fields [
    card_id: [type: :string, allow_nil?: false],
    count: [type: :integer, allow_nil?: false]
  ]

  @open_deck_player_fields [
    player_id: [type: :string, allow_nil?: false],
    deck_key: [type: :string, allow_nil?: false],
    cards: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @open_deck_card_fields]]
    ]
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
    define :get_supported_deck_blueprint, args: [:deck_key]
    define :create_from_supported_decks, args: [:players]

    define :create_from_decklists, args: [:players]

    define :create_from_decklists_with_seed,
      action: :create_from_decklists,
      args: [:players, :rng_seed]

    define :start_setup_command, args: [:game_id]
    define :call_coin_toss_command, args: [:game_id, :player_id, :call]

    define :choose_starting_player_command,
      args: [:game_id, :chooser_player_id, :starting_player_id]

    define :draw_opening_hand_command, args: [:game_id]
    define :choose_active_from_hand_command, args: [:game_id, :player_id, :card_instance_id]
    define :mulligan_opening_hand_command, args: [:game_id, :player_id]
    define :draw_mulligan_bonus_command, args: [:game_id, :player_id, :count]
    define :choose_setup_bench_from_hand_command, args: [:game_id, :player_id, :card_instance_id]
    define :finish_setup_choices_command, args: [:game_id, :player_id]
    define :place_prizes_command, args: [:game_id]
    define :complete_setup_command, args: [:game_id]
    define :start_next_turn_command, args: [:game_id]
    define :draw_for_turn_command, args: [:game_id, :player_id]
    define :skip_draw_for_turn_command, args: [:game_id, :player_id]
    define :open_action_window_command, args: [:game_id]
    define :play_card_command, args: [:game_id, :player_id, :card_instance_id]
    define :play_stadium_command, args: [:game_id, :player_id, :card_instance_id]
    define :use_team_rockets_factory_command, args: [:game_id, :player_id]

    define :use_munkidori_adrena_brain_command,
      args: [
        :game_id,
        :player_id,
        :source_card_instance_id,
        :from_card_instance_id,
        :target_card_instance_id,
        :damage_counters
      ]

    define :use_teal_mask_ogerpon_teal_dance_command,
      args: [:game_id, :player_id, :source_card_instance_id, :energy_card_instance_id]

    define :use_blaziken_ex_seething_spirit_command,
      args: [
        :game_id,
        :player_id,
        :source_card_instance_id,
        :energy_card_instance_id,
        :target_card_instance_id
      ]

    define :use_cursed_blast_command,
      args: [:game_id, :player_id, :source_card_instance_id, :target_card_instance_id]

    define :use_fezandipiti_flip_the_script_command,
      args: [:game_id, :player_id, :source_card_instance_id]

    define :use_noctowl_jewel_seeker_command,
      args: [:game_id, :player_id, :source_card_instance_id]

    define :use_psychic_draw_command, args: [:game_id, :player_id, :source_card_instance_id]

    define :use_drakloak_recon_directive_command,
      args: [:game_id, :player_id, :source_card_instance_id, :chosen_card_instance_id]

    define :use_dudunsparce_run_away_draw_command,
      args: [:game_id, :player_id, :source_card_instance_id]

    define :use_fan_rotom_fan_call_command, args: [:game_id, :player_id, :source_card_instance_id]
    define :play_basic_to_bench_command, args: [:game_id, :player_id, :card_instance_id]

    define :attach_tool_command,
      args: [:game_id, :player_id, :tool_card_instance_id, :target_card_instance_id]

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

    action :create_from_supported_decks, :struct do
      description "Create a TCG engine game from supported deck fixture keys."

      constraints instance_of: Game

      argument :players, {:array, :map} do
        allow_nil? false
        constraints items: [fields: @player_deck_selection_fields]
      end

      argument :active_player_id, :string
      argument :rng_seed, :string

      run fn input, _context ->
        opts =
          []
          |> maybe_put_opt(:active_player_id, Map.get(input.arguments, :active_player_id))
          |> maybe_put_opt(:rng_seed, Map.get(input.arguments, :rng_seed))

        SupportedDecks.create_game(input.arguments.players, opts)
      end
    end

    action :create_from_decklists, :struct do
      description "Create a TCG engine game from arbitrary catalog-backed deck payloads."

      constraints instance_of: Game

      argument :players, {:array, :map} do
        allow_nil? false
        constraints items: [fields: @open_deck_player_fields]
      end

      argument :active_player_id, :string
      argument :rng_seed, :string

      run fn input, _context ->
        opts =
          []
          |> maybe_put_opt(:active_player_id, Map.get(input.arguments, :active_player_id))
          |> maybe_put_opt(:rng_seed, Map.get(input.arguments, :rng_seed))

        Decklists.create_game(input.arguments.players, opts)
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

      accept [
        :active_player_id,
        :first_player_id,
        :rng_seed,
        :rng_seed_source,
        :rng_algorithm,
        :cursor_index,
        :latest_event_index
      ]
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
        :rng_seed,
        :rng_seed_source,
        :rng_algorithm,
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

    attribute :rng_seed, :string do
      sensitive? true
    end

    attribute :rng_seed_source, :string do
      public? true
    end

    attribute :rng_algorithm, :string do
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

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
