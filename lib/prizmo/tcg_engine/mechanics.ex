defmodule Prizmo.TcgEngine.Mechanics do
  @moduledoc """
  Transactional mechanics operations for the persisted TCG engine.

  This module is the first bridge from the old pure simulator toward composed Ash
  state machines. Public functions only persist accepted actions; rejected actions
  roll back before an event or snapshot is written.
  """

  import Prizmo.TcgEngine.AttackCosts, only: [require_attack_cost_paid: 3]

  import Prizmo.TcgEngine.BattleActions,
    only: [
      apply_attack_damage: 4,
      attached_energy_cards_for_retreat: 3,
      discard_knocked_out_stack: 2,
      discard_retreat_energy: 3,
      knockout_prize_count: 1,
      resolve_replacement_active_after_knockout: 2
    ]

  import Prizmo.TcgEngine.BoardState,
    only: [
      active_card: 2,
      maybe_finish_for_empty_board: 3,
      maybe_finish_for_last_prize: 2,
      require_all_players_have_active: 1,
      require_all_players_have_prizes: 2,
      require_no_active: 2,
      require_no_prizes_placed: 1,
      require_no_tool_attached: 2
    ]

  import Prizmo.TcgEngine.CardMetadataRequirements

  import Prizmo.TcgEngine.CardStore,
    only: [
      discard_cards_from_hand: 3,
      discard_existing_stadiums: 1,
      cards_in_zone: 3,
      get_card: 2,
      get_cards: 2,
      move_deck_card_to_hand: 3,
      move_deck_cards_to_bench: 4,
      move_discard_card_to_hand: 3,
      next_attachment_position: 2,
      next_bench_position: 2,
      next_discard_position: 2,
      next_hand_position_result: 2,
      reparent_attached_cards: 3
    ]

  import Prizmo.TcgEngine.EventLog,
    only: [write_event: 4, write_event_and_snapshot: 4, write_snapshot: 3]

  import Prizmo.TcgEngine.GameStore, only: [get_game: 1]
  import Prizmo.TcgEngine.Operation, only: [create: 3, transaction: 1, update: 3]
  import Prizmo.TcgEngine.PlayerStore, only: [get_player: 2]
  import Prizmo.TcgEngine.PromptStore, only: [get_prompt: 2]
  import Prizmo.TcgEngine.Requirements
  import Prizmo.TcgEngine.SetupStore, only: [get_setup: 1, require_setup_status: 2]
  import Prizmo.TcgEngine.TrainerPlay, only: [discard_trainer_card: 4, mark_trainer_flags: 2]
  import Prizmo.TcgEngine.TurnDraw, only: [draw_one_for_turn: 2]

  import Prizmo.TcgEngine.TurnFlow,
    only: [
      next_turn_number: 1,
      next_turn_player_id: 1,
      opponent_player_id: 2,
      require_action_window_for_player: 2,
      require_current_turn_status: 2
    ]

  import Prizmo.TcgEngine.TurnStore, only: [current_turn: 1]

  alias Prizmo.TcgEngine.AbilityEffects
  alias Prizmo.TcgEngine.AttackDamage
  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.AttackRequirements
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardPlay
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.ChoiceValidator
  alias Prizmo.TcgEngine.EnergyEffects
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Flow.Interpreter, as: FlowInterpreter
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameSetup
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.PendingEffects
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.RetreatCosts
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.SnapshotRestorer
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.ZoneActions

  require Ash.Query

  @type player_deck_source ::
          module() | %{required(:id) => String.t(), required(:card_ids) => [String.t()]}
  @type player_deck :: {String.t(), player_deck_source()}

  @spec create_game([player_deck()], keyword()) :: {:ok, Game.t()} | {:error, term()}
  def create_game(player_decks, opts \\ []) when is_list(player_decks) do
    active_player_id =
      Keyword.get(opts, :active_player_id, GameSetup.first_player_id(player_decks))

    transaction(fn ->
      with :ok <- GameSetup.require_two_players(player_decks),
           {:ok, game} <-
             GameSetup.create_game_record(active_player_id, rng_metadata: rng_metadata(opts)),
           {:ok, _players} <- GameSetup.create_players_and_cards(game, player_decks),
           {:ok, _snapshot} <- write_snapshot(game.id, nil, 0),
           {:ok, _shuffle_events} <- maybe_shuffle_opening_decks(game, player_decks, opts) do
        get_game(game.id)
      end
    end)
  end

  defp rng_metadata(opts) do
    case Keyword.get(opts, :rng_seed) do
      nil ->
        %{}

      seed ->
        %{
          rng_seed: seed,
          rng_seed_source: Keyword.get(opts, :rng_seed_source, "explicit"),
          rng_algorithm: Keyword.get(opts, :rng_algorithm, Rng.algorithm())
        }
    end
  end

  defp maybe_shuffle_opening_decks(%Game{} = game, player_decks, opts) do
    if Keyword.get(opts, :shuffle_decks?, false) do
      case Keyword.get(opts, :rng_seed) do
        seed when is_binary(seed) ->
          player_decks
          |> Enum.map(fn {player_id, deck} ->
            with {:ok, fact} <- GameSetup.shuffle_deck(game, player_id, deck, seed) do
              write_event_and_snapshot(
                game.id,
                :deck_shuffled,
                player_id,
                Map.delete(fact, :player_id)
              )
            end
          end)
          |> collect_results()

        nil ->
          {:error, :missing_rng_seed_for_shuffle}

        seed ->
          {:error, {:invalid_rng_seed, seed}}
      end
    else
      {:ok, []}
    end
  end

  @spec call_coin_toss(Game.t() | String.t(), String.t(), atom() | String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def call_coin_toss(game_or_id, player_id, call) when is_binary(player_id) do
    FlowInterpreter.dispatch(game_or_id, :call_coin_toss, %{player_id: player_id, call: call})
  end

  @spec choose_starting_player(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_starting_player(game_or_id, chooser_player_id, starting_player_id)
      when is_binary(chooser_player_id) and is_binary(starting_player_id) do
    FlowInterpreter.dispatch(game_or_id, :choose_starting_player, %{
      chooser_player_id: chooser_player_id,
      starting_player_id: starting_player_id
    })
  end

  @spec start_setup(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def start_setup(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, game} <- update(game, :start_setup, %{}),
           {:ok, _setup} <- create(Setup, :create, %{game_id: game.id}),
           {:ok, event} <- write_event(game, :start_setup, nil, %{}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec draw_opening_hand(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def draw_opening_hand(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, setup} <- get_setup(game.id),
           {:ok, setup} <- update(setup, :draw_opening_hand, %{}),
           :ok <- GameSetup.require_no_setup_cards_moved(game.id),
           {:ok, player_hand_facts} <- GameSetup.draw_opening_cards(game.id),
           {:ok, event} <-
             write_event(
               game,
               :draw_opening_hand,
               nil,
               setup_move_payload(setup, player_hand_facts)
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec choose_active_from_hand(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_active_from_hand(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    case get_game(game_or_id) do
      {:ok, %Game{flow_state: :setup_choosing_opening_active} = game} ->
        FlowInterpreter.dispatch(game, :choose_setup_active, %{
          player_id: player_id,
          card_instance_id: card_instance_id
        })

      {:ok, %Game{} = game} ->
        choose_active_from_hand_legacy(game, player_id, card_instance_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec mulligan_opening_hand(Game.t() | String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def mulligan_opening_hand(game_or_id, player_id) when is_binary(player_id) do
    FlowInterpreter.dispatch(game_or_id, :mulligan_opening_hand, %{player_id: player_id})
  end

  @spec draw_mulligan_bonus(Game.t() | String.t(), String.t(), pos_integer()) ::
          {:ok, Game.t()} | {:error, term()}
  def draw_mulligan_bonus(game_or_id, player_id, count)
      when is_binary(player_id) and is_integer(count) do
    FlowInterpreter.dispatch(game_or_id, :draw_mulligan_bonus, %{
      player_id: player_id,
      count: count
    })
  end

  defp choose_active_from_hand_legacy(%Game{} = game, player_id, card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game.id),
           {:ok, _setup} <- require_setup_status(game.id, :hands_drawn),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :hand),
           :ok <- require_basic_pokemon(card.card_id),
           :ok <- require_no_active(game.id, player_id),
           {:ok, _card} <- update(card, :choose_active, %{position: 1, turn_entered_play: 0}),
           {:ok, event} <-
             write_event(game, :choose_active_from_hand, player_id, %{card_instance_id: card.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec choose_setup_bench_from_hand(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_setup_bench_from_hand(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    case get_game(game_or_id) do
      {:ok, %Game{flow_state: :setup_choosing_opening_bench} = game} ->
        FlowInterpreter.dispatch(game, :choose_setup_bench, %{
          player_id: player_id,
          card_instance_id: card_instance_id
        })

      {:ok, %Game{} = game} ->
        choose_setup_bench_from_hand_legacy(game, player_id, card_instance_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp choose_setup_bench_from_hand_legacy(%Game{} = game, player_id, card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game.id),
           {:ok, _setup} <- require_setup_status(game.id, :hands_drawn),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :hand),
           :ok <- require_basic_pokemon(card.card_id),
           {:ok, position} <- next_bench_position(game.id, player_id),
           {:ok, _card} <-
             update(card, :play_to_bench, %{position: position, turn_entered_play: 0}),
           {:ok, event} <-
             write_event(game, :choose_setup_bench_from_hand, player_id, %{
               card_instance_id: card.id,
               position: position
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec finish_setup_choices(Game.t() | String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def finish_setup_choices(game_or_id, player_id) when is_binary(player_id) do
    FlowInterpreter.dispatch(game_or_id, :finish_setup_choices, %{player_id: player_id})
  end

  @spec pass_turn(Game.t() | String.t(), String.t()) :: {:ok, Game.t()} | {:error, term()}
  def pass_turn(game_or_id, player_id) when is_binary(player_id) do
    FlowInterpreter.dispatch(game_or_id, :pass, %{player_id: player_id})
  end

  @spec place_prizes(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def place_prizes(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, setup} <- require_setup_status(game.id, :hands_drawn),
           :ok <- require_all_players_have_active(game.id),
           :ok <- require_no_prizes_placed(game.id),
           {:ok, setup} <- update(setup, :place_prizes, %{}),
           {:ok, player_prize_facts} <- GameSetup.place_prize_cards(game.id),
           {:ok, event} <-
             write_event(game, :place_prizes, nil, setup_move_payload(setup, player_prize_facts)),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec complete_setup(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def complete_setup(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, setup} <- require_setup_status(game.id, :prizes_placed),
           :ok <- require_all_players_have_active(game.id),
           :ok <- require_all_players_have_prizes(game.id, 6),
           {:ok, setup} <- update(setup, :complete_setup, %{}),
           {:ok, game} <- update(game, :complete_setup, %{}),
           {:ok, event} <- write_event(game, :complete_setup, nil, %{setup_id: setup.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec start_next_turn(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def start_next_turn(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           {:ok, next_player_id} <- next_turn_player_id(game),
           {:ok, turn_number} <- next_turn_number(game.id),
           {:ok, next_player} <- get_player(game.id, next_player_id),
           {:ok, _player} <- update(next_player, :reset_turn_flags, %{}),
           {:ok, game} <- update(game, :set_active_player, %{active_player_id: next_player_id}),
           {:ok, turn} <-
             create(Turn, :create, %{
               game_id: game.id,
               turn_number: turn_number,
               active_player_id: next_player_id
             }),
           {:ok, event} <-
             write_event(game, :start_next_turn, next_player_id, %{turn_id: turn.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec play_basic_to_bench(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def play_basic_to_bench(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :hand),
           :ok <- require_basic_pokemon(card.card_id),
           {:ok, position} <- next_bench_position(game.id, player_id),
           {:ok, updated_card} <-
             update(card, :play_to_bench, %{
               position: position,
               turn_entered_play: turn.turn_number
             }),
           {:ok, risky_ruins_damage} <-
             StadiumEffects.apply_risky_ruins_if_needed(
               game.id,
               updated_card,
               turn.id,
               player_id
             ),
           event_payload =
             maybe_put(
               %{turn_id: turn.id, card_instance_id: card.id, position: position},
               :risky_ruins_damage,
               risky_ruins_damage
             ),
           {:ok, event} <-
             write_event(game, :play_basic_to_bench, player_id, event_payload),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec attach_energy(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def attach_energy(game_or_id, player_id, energy_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(energy_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, player} <- get_player(game.id, player_id),
           :ok <- require_energy_not_attached_this_turn(player),
           {:ok, energy_card} <- get_card(game.id, energy_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_card_owned_by_player(energy_card, player_id),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(energy_card, :hand),
           :ok <- require_in_play_pokemon_zone(target_card),
           :ok <- require_energy(energy_card.card_id),
           {:ok, position} <- next_attachment_position(game.id, target_card.id),
           {:ok, _energy_card} <-
             update(energy_card, :attach, %{
               attached_to_card_instance_id: target_card.id,
               position: position
             }),
           {:ok, recovered_special_condition} <-
             StadiumEffects.recover_special_condition(game.id, target_card),
           {:ok, _player} <- update(player, :mark_energy_attached, %{}),
           {:ok, _attach_event} <-
             write_event_and_snapshot(
               game.id,
               :attach_energy,
               player_id,
               maybe_put(
                 %{
                   turn_id: turn.id,
                   energy_card_instance_id: energy_card.id,
                   target_card_instance_id: target_card.id,
                   position: position
                 },
                 :recovered_special_condition,
                 recovered_special_condition
               )
             ),
           {:ok, effect_event} <-
             EnergyEffects.after_attach_from_hand(game, player, energy_card, target_card),
           {:ok, _effect_event} <-
             write_energy_attach_effect_event(game.id, player_id, turn.id, effect_event) do
        get_game(game.id)
      end
    end)
  end

  defp write_energy_attach_effect_event(_game_id, _player_id, _turn_id, nil), do: {:ok, nil}

  defp write_energy_attach_effect_event(game_id, player_id, turn_id, %{
         type: type,
         payload: payload
       }) do
    write_event_and_snapshot(game_id, type, player_id, Map.put(payload, :turn_id, turn_id))
  end

  @spec play_trainer_to_discard(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def play_trainer_to_discard(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :hand),
           {:ok, metadata} <- require_trainer_type(card.card_id, [:item, :supporter]),
           :ok <- require_supporter_available(player, metadata, game, turn),
           :ok <- require_ace_spec_available(player, metadata),
           {:ok, position} <- next_discard_position(game.id, player_id),
           {:ok, _card} <- update(card, :discard, %{position: position}),
           {:ok, _player} <- mark_trainer_flags(player, metadata),
           {:ok, event} <-
             write_event(game, :play_trainer_to_discard, player_id, %{
               turn_id: turn.id,
               card_instance_id: card.id,
               trainer_type: Atom.to_string(metadata.trainer_type)
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec buddy_buddy_poffin(Game.t() | String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, Game.t()} | {:error, term()}
  def buddy_buddy_poffin(game_or_id, player_id, poffin_card_instance_id, target_card_instance_ids)
      when is_binary(player_id) and is_binary(poffin_card_instance_id) and
             is_list(target_card_instance_ids) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- require_max_count(target_card_instance_ids, 2, :too_many_poffin_targets),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, poffin_card} <- get_card(game.id, poffin_card_instance_id),
           {:ok, targets} <- get_cards(game.id, target_card_instance_ids),
           :ok <-
             CardPlay.require_trainer_card(
               game,
               turn,
               player,
               poffin_card,
               player_id,
               "TEF-144",
               [:item]
             ),
           :ok <- require_all_owned_in_zone(targets, player_id, :deck),
           :ok <- require_poffin_targets(targets),
           {:ok, _poffin_card} <- discard_trainer_card(game, player, poffin_card, %{}),
           {:ok, moved_targets} <-
             move_deck_cards_to_bench(game.id, player_id, targets, turn.turn_number),
           {:ok, event} <-
             write_event(game, :buddy_buddy_poffin, player_id, %{
               turn_id: turn.id,
               instance_id: poffin_card.id,
               target_ids: Enum.map(moved_targets, & &1.id)
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec play_card(Game.t() | String.t(), String.t(), String.t(), map()) ::
          {:ok, Game.t()} | {:error, term()}
  def play_card(game_or_id, player_id, card_instance_id, opts \\ %{})
      when is_binary(player_id) and is_binary(card_instance_id) and is_map(opts) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, card} <- get_card(game.id, card_instance_id),
           {:ok, definition} <- EngineCardRegistry.fetch(card.card_id),
           {:ok, metadata} <-
             CardPlay.require_playable_trainer_definition(
               game,
               turn,
               player,
               card,
               player_id,
               definition
             ),
           {:ok, choices} <- ChoiceValidator.normalize_payload(opts, definition),
           :ok <-
             CardPlay.require_required_choices_available(
               game.id,
               player_id,
               card.id,
               definition
             ),
           {:ok, _event} <-
             write_event_and_snapshot(game.id, :card_play_started, player_id, %{
               turn_id: turn.id,
               card_instance_id: card.id,
               card_id: card.card_id
             }) do
        CardPlay.resolve_play_card_costs(game, turn, player, card, metadata, definition, choices)
      end
    end)
  end

  @spec choose_prompt(Game.t() | String.t(), String.t(), String.t(), term()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_prompt(game_or_id, player_id, prompt_id, choice)
      when is_binary(player_id) and is_binary(prompt_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, prompt} <- get_prompt(game.id, prompt_id),
           :ok <- require_prompt_awaiting_player(prompt, player_id),
           {:ok, pending_effect} <- PendingEffects.get(game.id, prompt.pending_effect_id),
           :ok <- require_pending_effect_status(pending_effect, :awaiting_prompt),
           choice_key = prompt_choice_key(prompt),
           {:ok, normalized_choice} <- ChoiceValidator.normalize_choice(choice) do
        resolve_prompt_choice(
          game,
          prompt,
          pending_effect,
          player_id,
          choice_key,
          normalized_choice
        )
      end
    end)
  end

  defp resolve_prompt_choice(
         %Game{} = game,
         %Prompt{} = prompt,
         %PendingEffect{source_type: :knockout_prize} = pending_effect,
         player_id,
         choice_key,
         selected_card_instance_ids
       ) do
    with {:ok, prize_count} <- prompt_exact_choice_count(prompt),
         :ok <- require_exact_count(selected_card_instance_ids, prize_count, :wrong_prize_count),
         :ok <- require_unique_ids(selected_card_instance_ids),
         :ok <- require_prompt_legal_choices(prompt, selected_card_instance_ids),
         {:ok, prize_cards} <- get_cards(game.id, selected_card_instance_ids),
         :ok <- require_all_owned_in_zone(prize_cards, player_id, :prize),
         {:ok, prompt} <- resolve_prompt(prompt, selected_card_instance_ids),
         {:ok, _event} <-
           write_prompt_resolved_event(game.id, prompt, pending_effect, player_id, choice_key),
         {:ok, pending_effect} <-
           update(pending_effect, :resume, %{
             current_player_id: nil,
             state:
               Map.put(pending_effect.state || %{}, "last_choice", selected_card_instance_ids)
           }),
         {:ok, taken_prize_cards} <- take_prize_cards(game.id, player_id, prize_cards),
         {:ok, _pending_effect} <-
           update(pending_effect, :complete, %{
             current_player_id: nil,
             state:
               Map.put(
                 pending_effect.state || %{},
                 "taken_prize_card_instance_ids",
                 Enum.map(taken_prize_cards, & &1.id)
               )
           }),
         {:ok, game} <- maybe_finish_for_last_prize(game, player_id),
         {:ok, event} <-
           write_event(game, :take_knockout_prizes, player_id, %{
             turn_id: current_turn_id(game.id),
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             prize_count: prize_count,
             taken_prize_card_instance_ids: Enum.map(taken_prize_cards, & &1.id),
             knocked_out_card_instance_id:
               Map.get(pending_effect.state || %{}, "knocked_out_card_instance_id"),
             knocked_out_card_instance_ids: pending_knockout_card_instance_ids(pending_effect),
             knocked_out_player_id: Map.get(pending_effect.state || %{}, "knocked_out_player_id"),
             knocked_out_player_ids: pending_knockout_player_ids(pending_effect),
             knockouts: Map.get(pending_effect.state || %{}, "knockouts", []),
             winner_player_id: game.winner_player_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
         {:ok, game} <- get_game(game.id),
         {:ok, game} <- maybe_create_queued_knockout_prize_selection(game, pending_effect) do
      stabilize_flow(game)
    end
  end

  defp resolve_prompt_choice(
         %Game{} = game,
         %Prompt{} = prompt,
         %PendingEffect{source_type: :attack_effect} = pending_effect,
         player_id,
         choice_key,
         normalized_choice
       ) do
    with {:ok, prompt} <- resolve_prompt(prompt, normalized_choice),
         {:ok, _event} <-
           write_prompt_resolved_event(game.id, prompt, pending_effect, player_id, choice_key),
         {:ok, pending_effect} <-
           update(pending_effect, :resume, %{
             current_player_id: nil,
             state: Map.put(pending_effect.state || %{}, "last_choice", normalized_choice)
           }) do
      AttackEffects.resume_pending_effect(
        game,
        prompt,
        pending_effect,
        player_id,
        choice_key,
        normalized_choice
      )
    end
  end

  defp resolve_prompt_choice(
         %Game{} = game,
         %Prompt{} = prompt,
         %PendingEffect{} = pending_effect,
         player_id,
         choice_key,
         normalized_choice
       ) do
    with {:ok, prompt} <- resolve_prompt(prompt, normalized_choice),
         {:ok, _event} <-
           write_prompt_resolved_event(game.id, prompt, pending_effect, player_id, choice_key),
         {:ok, pending_effect} <-
           update(pending_effect, :resume, %{
             current_player_id: nil,
             state: Map.put(pending_effect.state || %{}, "last_choice", normalized_choice)
           }) do
      CardPlay.resume_pending_effect(game, pending_effect, choice_key, normalized_choice)
    end
  end

  defp resolve_prompt(%Prompt{} = prompt, normalized_choice) do
    update(prompt, :resolve, %{
      payload: Map.put(prompt.payload, "resolved_choice", normalized_choice)
    })
  end

  defp write_prompt_resolved_event(game_id, prompt, pending_effect, player_id, choice_key) do
    write_event_and_snapshot(game_id, :prompt_resolved, player_id, %{
      prompt_id: prompt.id,
      pending_effect_id: pending_effect.id,
      choice_key: choice_key,
      choice: Map.get(prompt.payload, "resolved_choice", [])
    })
  end

  defp prompt_exact_choice_count(%Prompt{payload: payload}) do
    case {Map.get(payload, "min"), Map.get(payload, "max")} do
      {count, count} when is_integer(count) and count >= 0 -> {:ok, count}
      {min, max} -> {:error, {:unsupported_prompt_choice_count, min, max}}
    end
  end

  defp require_prompt_legal_choices(%Prompt{payload: payload}, selected_card_instance_ids) do
    legal_choice_ids =
      case Map.get(payload, "legal_choices", []) do
        ids when is_list(ids) -> ids
        _other -> []
      end

    if Enum.all?(selected_card_instance_ids, &(&1 in legal_choice_ids)) do
      :ok
    else
      {:error, :illegal_prompt_choice}
    end
  end

  defp take_prize_cards(game_id, player_id, prize_cards) do
    prize_cards
    |> Enum.map(fn prize_card ->
      with {:ok, position} <- next_hand_position_result(game_id, player_id) do
        update(prize_card, :take_prize, %{position: position})
      end
    end)
    |> collect_results()
  end

  @spec ultra_ball(Game.t() | String.t(), String.t(), String.t(), [String.t()], String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def ultra_ball(
        game_or_id,
        player_id,
        ultra_ball_card_instance_id,
        discard_card_instance_ids,
        target_card_instance_id
      )
      when is_binary(player_id) and is_binary(ultra_ball_card_instance_id) and
             is_list(discard_card_instance_ids) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <-
             require_exact_count(discard_card_instance_ids, 2, :wrong_ultra_ball_discard_count),
           :ok <- require_unique_ids(discard_card_instance_ids),
           :ok <- require_id_not_in(ultra_ball_card_instance_id, discard_card_instance_ids),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, ultra_ball_card} <- get_card(game.id, ultra_ball_card_instance_id),
           {:ok, discard_cards} <- get_cards(game.id, discard_card_instance_ids),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <-
             CardPlay.require_trainer_card(
               game,
               turn,
               player,
               ultra_ball_card,
               player_id,
               "MEG-131",
               [:item]
             ),
           :ok <- require_all_owned_in_zone(discard_cards, player_id, :hand),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(target_card, :deck),
           :ok <- require_pokemon_card(target_card.card_id),
           {:ok, _ultra_ball_card} <- discard_trainer_card(game, player, ultra_ball_card, %{}),
           {:ok, _discarded_cards} <- discard_cards_from_hand(game.id, player_id, discard_cards),
           {:ok, moved_target} <- move_deck_card_to_hand(game.id, player_id, target_card),
           {:ok, event} <-
             write_event(game, :ultra_ball, player_id, %{
               turn_id: turn.id,
               instance_id: ultra_ball_card.id,
               discard_ids: Enum.map(discard_cards, & &1.id),
               target_id: moved_target.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec boss_orders(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def boss_orders(game_or_id, player_id, boss_card_instance_id, target_bench_card_instance_id)
      when is_binary(player_id) and is_binary(boss_card_instance_id) and
             is_binary(target_bench_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, boss_card} <- get_card(game.id, boss_card_instance_id),
           {:ok, opponent_player_id} <- opponent_player_id(game.id, player_id),
           {:ok, opponent_active_card} <- active_card(game.id, opponent_player_id),
           {:ok, target_bench_card} <- get_card(game.id, target_bench_card_instance_id),
           :ok <-
             CardPlay.require_trainer_card(
               game,
               turn,
               player,
               boss_card,
               player_id,
               "MEG-114",
               [:supporter]
             ),
           :ok <- require_card_owned_by_player(target_bench_card, opponent_player_id),
           :ok <- require_card_zone(target_bench_card, :bench),
           {:ok, _boss_card} <- discard_trainer_card(game, player, boss_card, %{}),
           bench_position = target_bench_card.position,
           {:ok, _opponent_active_card} <-
             update(opponent_active_card, :move_active_to_bench, %{
               position: bench_position,
               status: nil
             }),
           {:ok, _target_bench_card} <-
             update(target_bench_card, :promote_to_active, %{position: 1, status: nil}),
           {:ok, event} <-
             write_event(game, :boss_orders, player_id, %{
               turn_id: turn.id,
               instance_id: boss_card.id,
               target_id: target_bench_card.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec night_stretcher(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def night_stretcher(game_or_id, player_id, stretcher_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(stretcher_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, stretcher_card} <- get_card(game.id, stretcher_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <-
             CardPlay.require_trainer_card(
               game,
               turn,
               player,
               stretcher_card,
               player_id,
               "ASC-196",
               [:item]
             ),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(target_card, :discard),
           :ok <- require_night_stretcher_target(target_card.card_id),
           {:ok, _stretcher_card} <- discard_trainer_card(game, player, stretcher_card, %{}),
           {:ok, moved_target} <- move_discard_card_to_hand(game.id, player_id, target_card),
           {:ok, event} <-
             write_event(game, :night_stretcher, player_id, %{
               turn_id: turn.id,
               instance_id: stretcher_card.id,
               target_id: moved_target.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec poke_pad(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def poke_pad(game_or_id, player_id, poke_pad_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(poke_pad_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, poke_pad_card} <- get_card(game.id, poke_pad_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <-
             CardPlay.require_trainer_card(
               game,
               turn,
               player,
               poke_pad_card,
               player_id,
               "POR-081",
               [:item]
             ),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(target_card, :deck),
           :ok <- require_non_rule_box_pokemon_card(target_card.card_id),
           {:ok, _poke_pad_card} <- discard_trainer_card(game, player, poke_pad_card, %{}),
           {:ok, moved_target} <- move_deck_card_to_hand(game.id, player_id, target_card),
           {:ok, event} <-
             write_event(game, :poke_pad, player_id, %{
               turn_id: turn.id,
               instance_id: poke_pad_card.id,
               target_id: moved_target.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec play_stadium(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def play_stadium(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :hand),
           {:ok, metadata} <- require_trainer_type(card.card_id, [:stadium]),
           :ok <- require_ace_spec_available(player, metadata),
           {:ok, _discarded_stadiums} <- discard_existing_stadiums(game.id),
           {:ok, _card} <- update(card, :play_stadium, %{position: 1}),
           {:ok, recovered_special_conditions} <-
             StadiumEffects.recover_special_conditions(game.id),
           {:ok, _player} <- mark_trainer_flags(player, metadata),
           {:ok, event} <-
             write_event(
               game,
               :play_stadium,
               player_id,
               maybe_put_non_empty(
                 %{
                   turn_id: turn.id,
                   card_instance_id: card.id
                 },
                 :recovered_special_conditions,
                 recovered_special_conditions
               )
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec use_team_rockets_factory(Game.t() | String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_team_rockets_factory(game_or_id, player_id) when is_binary(player_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, %CardInstance{} = stadium_card} <-
             StadiumEffects.active_team_rockets_factory(game.id),
           :ok <-
             StadiumEffects.require_team_rockets_factory_available(game.id, turn.id, player_id),
           {:ok, %{effect: %{count: draw_count}}} <- CardCatalog.fetch(stadium_card.card_id),
           {:ok, drawn_cards} <- draw_team_rockets_factory_cards(game.id, player, draw_count),
           {:ok, _event} <-
             write_event_and_snapshot(game.id, :stadium_effect_used, player_id, %{
               turn_id: turn.id,
               source: EventPayloads.card_source(stadium_card),
               effect_key: :draw_after_playing_team_rocket_supporter,
               affected_player_id: player_id,
               card_count: length(drawn_cards),
               cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand),
               public_note: team_rockets_factory_public_note(player_id, length(drawn_cards))
             }) do
        get_game(game.id)
      end
    end)
  end

  @spec use_munkidori_adrena_brain(
          Game.t() | String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer()
        ) :: {:ok, Game.t()} | {:error, term()}
  def use_munkidori_adrena_brain(
        game_or_id,
        player_id,
        source_card_instance_id,
        from_card_instance_id,
        target_card_instance_id,
        damage_counters
      )
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(from_card_instance_id) and
             is_binary(target_card_instance_id) and is_integer(damage_counters) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           {:ok, from_card} <- get_card(game.id, from_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           {:ok, opponent_player_id} <- opponent_player_id(game.id, player_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_adrena_brain_available(game.id, source_card, turn),
           :ok <- require_card_owned_by_player(from_card, player_id),
           :ok <- require_in_play_pokemon_zone(from_card),
           :ok <- AbilityEffects.require_damage_counter_count(damage_counters, from_card),
           :ok <- require_card_owned_by_player(target_card, opponent_player_id),
           :ok <- require_in_play_pokemon_zone(target_card),
           {:ok, ability_result} <-
             move_adrena_brain_damage_counters(
               game.id,
               source_card,
               from_card,
               target_card,
               turn,
               damage_counters
             ),
           {:ok, event} <-
             write_event(
               game,
               :ability_used,
               player_id,
               adrena_brain_event_payload(
                 turn,
                 source_card,
                 from_card,
                 target_card,
                 ability_result
               )
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        resolve_adrena_brain_knockout(
          game.id,
          player_id,
          target_card.owner_player_id,
          target_card,
          ability_result
        )
      end
    end)
  end

  @spec attach_tool(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def attach_tool(game_or_id, player_id, tool_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(tool_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :action_window),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, tool_card} <- get_card(game.id, tool_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_card_owned_by_player(tool_card, player_id),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(tool_card, :hand),
           :ok <- require_in_play_pokemon_zone(target_card),
           {:ok, metadata} <- require_trainer_type(tool_card.card_id, [:tool]),
           :ok <- require_ace_spec_available(player, metadata),
           :ok <- require_no_tool_attached(game.id, target_card.id),
           {:ok, position} <- next_attachment_position(game.id, target_card.id),
           {:ok, _tool_card} <-
             update(tool_card, :attach, %{
               attached_to_card_instance_id: target_card.id,
               position: position
             }),
           {:ok, _player} <- mark_trainer_flags(player, metadata),
           {:ok, event} <-
             write_event(game, :attach_tool, player_id, %{
               turn_id: turn.id,
               tool_card_instance_id: tool_card.id,
               target_card_instance_id: target_card.id,
               position: position
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec search_deck_to_hand(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def search_deck_to_hand(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    ZoneActions.move_owned_card_to_hand_from_zone(
      game_or_id,
      player_id,
      card_instance_id,
      :deck,
      :search_deck_to_hand
    )
  end

  @spec put_basic_from_deck_to_bench(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def put_basic_from_deck_to_bench(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, card} <- get_card(game.id, card_instance_id),
           :ok <- require_card_owned_by_player(card, player_id),
           :ok <- require_card_zone(card, :deck),
           :ok <- require_basic_pokemon(card.card_id),
           {:ok, position} <- next_bench_position(game.id, player_id),
           {:ok, _card} <-
             update(card, :put_basic_from_deck_to_bench, %{
               position: position,
               turn_entered_play: turn.turn_number
             }),
           {:ok, event} <-
             write_event(game, :put_basic_from_deck_to_bench, player_id, %{
               turn_id: turn.id,
               card_instance_id: card.id,
               position: position
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec evolve_from_hand(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def evolve_from_hand(game_or_id, player_id, evolution_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(evolution_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- require_evolution_allowed_this_turn(turn),
           {:ok, evolution_card} <- get_card(game.id, evolution_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_card_owned_by_player(evolution_card, player_id),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(evolution_card, :hand),
           :ok <- require_in_play_pokemon_zone(target_card),
           :ok <-
             StadiumEffects.require_or_waive_same_turn_evolution(
               game.id,
               target_card,
               evolution_card.card_id,
               turn
             ),
           :ok <- require_evolves_from(evolution_card.card_id, target_card.card_id),
           evolve_action = evolve_action_for_zone(target_card.zone),
           target_position = target_card.position,
           {:ok, evolution_card} <-
             update(evolution_card, evolve_action, %{
               evolves_from_card_instance_id: target_card.id,
               position: target_position,
               damage: target_card.damage,
               status: nil,
               turn_entered_play: turn.turn_number
             }),
           {:ok, reparented_attachments} <-
             reparent_attached_cards(game.id, target_card.id, evolution_card.id),
           {:ok, _target_card} <-
             update(target_card, :evolve_under, %{
               attached_to_card_instance_id: evolution_card.id,
               damage: 0,
               status: nil,
               position: 1
             }),
           {:ok, event} <-
             write_event(game, :evolve_from_hand, player_id, %{
               turn_id: turn.id,
               evolution_card_instance_id: evolution_card.id,
               target_card_instance_id: target_card.id,
               preserved_damage: target_card.damage,
               cleared_status: if(target_card.status, do: Atom.to_string(target_card.status)),
               preserved_attachment_card_instance_ids: Enum.map(reparented_attachments, & &1.id)
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec discard_from_hand(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def discard_from_hand(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    ZoneActions.discard_owned_card_from_zone(
      game_or_id,
      player_id,
      card_instance_id,
      :hand,
      :discard_from_hand
    )
  end

  @spec discard_from_deck(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def discard_from_deck(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    ZoneActions.discard_owned_card_from_zone(
      game_or_id,
      player_id,
      card_instance_id,
      :deck,
      :discard_from_deck
    )
  end

  @spec recover_discard_to_hand(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def recover_discard_to_hand(game_or_id, player_id, card_instance_id)
      when is_binary(player_id) and is_binary(card_instance_id) do
    ZoneActions.move_owned_card_to_hand_from_zone(
      game_or_id,
      player_id,
      card_instance_id,
      :discard,
      :recover_discard_to_hand
    )
  end

  @spec switch_active_with_bench(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def switch_active_with_bench(game_or_id, player_id, bench_card_instance_id)
      when is_binary(player_id) and is_binary(bench_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, active_card} <- active_card(game.id, player_id),
           {:ok, bench_card} <- get_card(game.id, bench_card_instance_id),
           :ok <- require_card_owned_by_player(bench_card, player_id),
           :ok <- require_card_zone(bench_card, :bench),
           bench_position = bench_card.position,
           {:ok, _active_card} <-
             update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
           {:ok, _bench_card} <-
             update(bench_card, :promote_to_active, %{position: 1, status: nil}),
           {:ok, event} <-
             write_event(game, :switch_active_with_bench, player_id, %{
               turn_id: turn.id,
               active_card_instance_id: active_card.id,
               bench_card_instance_id: bench_card.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec retreat(Game.t() | String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, Game.t()} | {:error, term()}
  def retreat(game_or_id, player_id, bench_card_instance_id, energy_card_instance_ids)
      when is_binary(player_id) and is_binary(bench_card_instance_id) and
             is_list(energy_card_instance_ids) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, player} <- get_player(game.id, player_id),
           :ok <- require_not_retreated_this_turn(player),
           {:ok, active_card} <- active_card(game.id, player_id),
           :ok <- require_can_retreat(active_card, turn),
           {:ok, bench_card} <- get_card(game.id, bench_card_instance_id),
           :ok <- require_card_owned_by_player(bench_card, player_id),
           :ok <- require_card_zone(bench_card, :bench),
           {:ok, retreat_cost_details} <-
             RetreatCosts.effective_retreat_cost_details(game.id, active_card),
           :ok <-
             require_retreat_cost_paid(retreat_cost_details.effective, energy_card_instance_ids),
           {:ok, energy_cards} <-
             attached_energy_cards_for_retreat(game.id, active_card.id, energy_card_instance_ids),
           {:ok, _discarded_energy} <- discard_retreat_energy(game.id, player_id, energy_cards),
           bench_position = bench_card.position,
           {:ok, _active_card} <-
             update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
           {:ok, _bench_card} <-
             update(bench_card, :promote_to_active, %{position: 1, status: nil}),
           {:ok, _player} <- update(player, :mark_retreated, %{}),
           {:ok, event} <-
             write_event(game, :retreat, player_id, %{
               turn_id: turn.id,
               active_card_instance_id: active_card.id,
               bench_card_instance_id: bench_card.id,
               printed_retreat_cost: retreat_cost_details.printed,
               effective_retreat_cost: retreat_cost_details.effective,
               retreat_cost_reduction: retreat_cost_details.reduction,
               retreat_cost_reduction_card_instance_ids:
                 retreat_cost_details.reduction_card_instance_ids,
               discarded_energy_card_instance_ids: Enum.map(energy_cards, & &1.id)
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec choose_prize(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_prize(game_or_id, player_id, prize_card_instance_id)
      when is_binary(player_id) and is_binary(prize_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           {:ok, prize_card} <- get_card(game.id, prize_card_instance_id),
           :ok <- require_card_owned_by_player(prize_card, player_id),
           :ok <- require_card_zone(prize_card, :prize),
           {:ok, position} <- next_hand_position_result(game.id, player_id),
           {:ok, _prize_card} <- update(prize_card, :take_prize, %{position: position}),
           {:ok, game} <- maybe_finish_for_last_prize(game, player_id),
           {:ok, event} <-
             write_event(game, :choose_prize, player_id, %{
               prize_card_instance_id: prize_card.id,
               position: position
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec choose_replacement_active(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def choose_replacement_active(game_or_id, player_id, bench_card_instance_id)
      when is_binary(player_id) and is_binary(bench_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_no_active(game.id, player_id),
           {:ok, bench_card} <- get_card(game.id, bench_card_instance_id),
           :ok <- require_card_owned_by_player(bench_card, player_id),
           :ok <- require_card_zone(bench_card, :bench),
           {:ok, _bench_card} <-
             update(bench_card, :promote_to_active, %{position: 1, status: nil}),
           {:ok, event} <-
             write_event(game, :choose_replacement_active, player_id, %{
               bench_card_instance_id: bench_card.id
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
           {:ok, game} <- get_game(game.id) do
        stabilize_flow(game)
      end
    end)
  end

  @spec resolve_attack_damage(Game.t() | String.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, Game.t()} | {:error, term()}
  def resolve_attack_damage(game_or_id, attacking_player_id, target_card_instance_id, damage)
      when is_binary(attacking_player_id) and is_binary(target_card_instance_id) and
             is_integer(damage) and damage >= 0 do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_in_play_pokemon_zone(target_card),
           {:ok, damage_result} <-
             apply_attack_damage(game.id, attacking_player_id, target_card, damage),
           {:ok, event} <-
             write_event(
               game,
               :resolve_attack_damage,
               attacking_player_id,
               Map.merge(
                 %{target_card_instance_id: target_card.id},
                 attack_damage_payload(damage_result)
               )
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        resolve_knockout_after_attack_damage(
          game.id,
          attacking_player_id,
          target_card.owner_player_id,
          target_card,
          damage_result
        )
      end
    end)
  end

  @spec set_pokemon_status(Game.t() | String.t(), String.t(), String.t(), atom() | nil) ::
          {:ok, Game.t()} | {:error, term()}
  def set_pokemon_status(game_or_id, player_id, target_card_instance_id, status)
      when is_binary(player_id) and is_binary(target_card_instance_id) and
             (is_atom(status) or is_nil(status)) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_in_play_pokemon_zone(target_card),
           :ok <- require_supported_status(status),
           {:ok, status_payload} <- maybe_set_pokemon_status(game.id, target_card, status),
           {:ok, event} <-
             write_event(
               game,
               :set_pokemon_status,
               player_id,
               Map.merge(
                 %{
                   target_card_instance_id: target_card.id,
                   status: if(status, do: Atom.to_string(status))
                 },
                 status_payload
               )
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  defp maybe_set_pokemon_status(game_id, %CardInstance{} = target_card, status) do
    case StadiumEffects.status_condition_prevention_payload(game_id, target_card, status) do
      {:prevented, prevention_payload} ->
        {:ok, Map.put(prevention_payload, :status_applied?, false)}

      :not_prevented ->
        with {:ok, _target_card} <- update(target_card, :set_status, %{status: status}) do
          {:ok, %{status_applied?: true}}
        end
    end
  end

  @spec declare_attack(Game.t() | String.t(), String.t(), atom() | String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def declare_attack(game_or_id, player_id, attack_id)
      when is_binary(player_id) and (is_atom(attack_id) or is_binary(attack_id)) do
    case get_game(game_or_id) do
      {:ok, %Game{flow_state: :turn_action_window} = game} ->
        FlowInterpreter.dispatch(game, :declare_attack, %{
          player_id: player_id,
          attack_id: attack_id
        })

      {:ok, %Game{} = game} ->
        declare_attack_legacy(game, player_id, attack_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def declare_attack_legacy(game_or_id, player_id, attack_id)
      when is_binary(player_id) and (is_atom(attack_id) or is_binary(attack_id)) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           {:ok, attacker_card} <- active_card(game.id, player_id),
           :ok <- require_can_attack(attacker_card, turn),
           :ok <- AttackRequirements.require_card_attack_restrictions(game.id, attacker_card),
           {:ok, defender_player_id} <- opponent_player_id(game.id, player_id),
           {:ok, defender_card} <- active_card(game.id, defender_player_id),
           {:ok, attack} <- CardCatalog.fetch_attack(attacker_card.card_id, attack_id),
           :ok <- AttackEffects.require_declarable_attack(attack, defender_card),
           :ok <- require_attack_cost_paid(game.id, attacker_card, attack),
           {:ok, turn} <-
             update(turn, :declare_attack, %{
               pending_attack_id: attack.id,
               pending_attacker_card_instance_id: attacker_card.id,
               pending_defender_card_instance_id: defender_card.id
             }),
           {:ok, event} <-
             write_event(game, :declare_attack, player_id, %{
               turn_id: turn.id,
               attacker_card_instance_id: attacker_card.id,
               defender_card_instance_id: defender_card.id,
               attack_id: Atom.to_string(attack.id),
               attack_cost: Prizmo.TcgEngine.AttackCosts.stringify_cost(attack.cost)
             }),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec resolve_declared_attack(Game.t() | String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  @spec resolve_declared_attack(Game.t() | String.t(), String.t(), map()) ::
          {:ok, Game.t()} | {:error, term()}
  def resolve_declared_attack(game_or_id, player_id, opts \\ %{})

  def resolve_declared_attack(game_or_id, player_id, opts)
      when is_binary(player_id) and is_map(opts) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :attack_declared),
           :ok <- require_turn_player(turn, player_id),
           {:ok, attacker_card} <- get_card(game.id, turn.pending_attacker_card_instance_id),
           {:ok, defender_card} <- get_card(game.id, turn.pending_defender_card_instance_id),
           {:ok, attack} <-
             CardCatalog.fetch_attack(attacker_card.card_id, turn.pending_attack_id),
           {:ok, {effective_attack, copied_attack_payload}} <-
             AttackEffects.effective_attack_for_resolution(defender_card, attack, opts),
           {:ok, damage} <-
             AttackDamage.damage_for(attacker_card, defender_card, effective_attack, opts),
           {:ok, turn} <- update(turn, :resolve_attack, %{}),
           {:ok, damage_result} <-
             apply_attack_damage(game.id, player_id, defender_card, damage),
           {:ok, effect_payload} <-
             AttackEffects.resolve_after_damage(
               game.id,
               player_id,
               attacker_card,
               defender_card,
               effective_attack,
               opts
             ),
           {:ok, handheld_fan_payload} <-
             ToolEffects.apply_handheld_fan_if_needed(
               game.id,
               player_id,
               attacker_card,
               defender_card,
               damage_result,
               opts
             ),
           {:ok, event} <-
             write_event(
               game,
               :resolve_declared_attack,
               player_id,
               %{
                 turn_id: turn.id,
                 attack_id: Atom.to_string(turn.pending_attack_id),
                 defender_card_instance_id: defender_card.id
               }
               |> Map.merge(attack_damage_payload(damage_result))
               |> Map.merge(
                 AttackEffects.merge_copied_attack_payload(copied_attack_payload, effect_payload)
               )
               |> maybe_put(:handheld_fan_energy_moved, handheld_fan_payload)
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        with {:ok, prize_selections} <-
               knockout_prize_selections_after_attack(
                 game.id,
                 player_id,
                 defender_card.owner_player_id,
                 defender_card,
                 attacker_card,
                 damage_result,
                 effect_payload
               ),
             {:ok, game} <- create_knockout_prize_selections(game.id, prize_selections),
             {:ok, game} <-
               resolve_active_replacement_after_attack_damage(
                 game,
                 player_id,
                 defender_card.owner_player_id,
                 damage_result
               ) do
          resolve_self_replacement_after_attack_effect(
            game,
            player_id,
            defender_card.owner_player_id,
            effect_payload
          )
        end
      end
    end)
  end

  @spec finish_attack(Game.t() | String.t(), String.t()) :: {:ok, Game.t()} | {:error, term()}
  def finish_attack(game_or_id, player_id) when is_binary(player_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- require_current_turn_status(game.id, :attack_resolving),
           :ok <- require_turn_player(turn, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           :ok <- require_all_players_have_active(game.id),
           {:ok, turn} <- update(turn, :finish_attack, %{}),
           {:ok, event} <- write_event(game, :finish_attack, player_id, %{turn_id: turn.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  defp resolve_active_replacement_after_attack_damage(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id,
         %{
           knocked_out?: true
         }
       ) do
    resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
  end

  defp resolve_active_replacement_after_attack_damage(
         %Game{} = game,
         _attacking_player_id,
         _knocked_out_player_id,
         _damage_result
       ) do
    {:ok, game}
  end

  defp knockout_prize_selections_after_attack(
         game_id,
         attacking_player_id,
         defender_player_id,
         defender_card,
         attacker_card,
         damage_result,
         effect_payload
       ) do
    with {:ok, attack_records} <-
           attack_knockout_prize_records(
             game_id,
             defender_player_id,
             defender_card,
             damage_result,
             effect_payload
           ),
         {:ok, self_records} <-
           self_knockout_prize_records(
             game_id,
             attacking_player_id,
             attacker_card,
             effect_payload
           ) do
      {:ok,
       []
       |> append_knockout_prize_selection(attacking_player_id, attack_records)
       |> append_knockout_prize_selection(defender_player_id, self_records)}
    end
  end

  defp resolve_knockout_after_attack_damage(
         game_id,
         attacking_player_id,
         knocked_out_player_id,
         target_card,
         %{knocked_out?: true} = damage_result
       ) do
    with {:ok, prize_records} <-
           active_knockout_prize_records(
             game_id,
             knocked_out_player_id,
             target_card,
             damage_result
           ),
         {:ok, game} <-
           create_knockout_prize_selections(game_id, [
             %{player_id: attacking_player_id, prize_records: prize_records}
           ]) do
      resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
    end
  end

  defp resolve_knockout_after_attack_damage(
         game_id,
         _attacking_player_id,
         _knocked_out_player_id,
         _target_card,
         _damage_result
       ) do
    get_game(game_id)
  end

  defp attack_knockout_prize_records(
         game_id,
         knocked_out_player_id,
         target_card,
         damage_result,
         effect_payload
       ) do
    with {:ok, active_records} <-
           active_knockout_prize_records(
             game_id,
             knocked_out_player_id,
             target_card,
             damage_result
           ),
         {:ok, bench_records} <- bench_knockout_prize_records(game_id, effect_payload) do
      {:ok, active_records ++ bench_records}
    end
  end

  defp active_knockout_prize_records(game_id, knocked_out_player_id, target_card, %{
         knocked_out?: true
       }) do
    with {:ok, current_target_card} <- get_card(game_id, target_card.id),
         :ok <- require_card_zone(current_target_card, :discard),
         {:ok, prize_record} <- knockout_prize_record(knocked_out_player_id, current_target_card) do
      {:ok, [prize_record]}
    end
  end

  defp active_knockout_prize_records(
         _game_id,
         _knocked_out_player_id,
         _target_card,
         _damage_result
       ) do
    {:ok, []}
  end

  defp bench_knockout_prize_records(game_id, effect_payload) do
    effect_payload
    |> bench_knockout_card_instance_ids()
    |> Enum.map(fn bench_card_instance_id ->
      with {:ok, target_card} <- get_card(game_id, bench_card_instance_id),
           :ok <- require_card_zone(target_card, :discard) do
        knockout_prize_record(target_card.owner_player_id, target_card)
      end
    end)
    |> collect_results()
  end

  defp knockout_prize_record(knocked_out_player_id, target_card) do
    with {:ok, prize_count} <- knockout_prize_count(target_card) do
      {:ok,
       %{
         knocked_out_card_id: target_card.card_id,
         knocked_out_card_instance_id: target_card.id,
         knocked_out_player_id: knocked_out_player_id,
         prize_count: prize_count
       }}
    end
  end

  defp bench_knockout_card_instance_ids(%{bench_knocked_out?: true} = effect_payload) do
    case Map.get(effect_payload, :bench_damage_target_card_instance_id) do
      card_instance_id when is_binary(card_instance_id) -> [card_instance_id]
      _missing -> []
    end
  end

  defp bench_knockout_card_instance_ids(%{bench_damage_counter_allocations: allocations})
       when is_list(allocations) do
    allocations
    |> Enum.filter(&Map.get(&1, :knocked_out?, false))
    |> Enum.map(&Map.get(&1, :card_instance_id))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp bench_knockout_card_instance_ids(_effect_payload), do: []

  defp self_knockout_prize_records(game_id, knocked_out_player_id, attacker_card, %{
         self_knocked_out?: true
       }) do
    with {:ok, current_attacker_card} <- get_card(game_id, attacker_card.id),
         :ok <- require_card_zone(current_attacker_card, :discard),
         {:ok, prize_record} <-
           knockout_prize_record(knocked_out_player_id, current_attacker_card) do
      {:ok, [prize_record]}
    end
  end

  defp self_knockout_prize_records(
         _game_id,
         _knocked_out_player_id,
         _attacker_card,
         _effect_payload
       ) do
    {:ok, []}
  end

  defp append_knockout_prize_selection(selections, _player_id, []) do
    selections
  end

  defp append_knockout_prize_selection(selections, player_id, prize_records) do
    case Enum.find_index(selections, &(&1.player_id == player_id)) do
      nil ->
        selections ++ [%{player_id: player_id, prize_records: prize_records}]

      index ->
        List.update_at(selections, index, fn selection ->
          %{selection | prize_records: selection.prize_records ++ prize_records}
        end)
    end
  end

  defp resolve_self_replacement_after_attack_effect(
         %Game{status: :finished} = game,
         _attacking_player_id,
         _defender_player_id,
         _effect_payload
       ) do
    {:ok, game}
  end

  defp resolve_self_replacement_after_attack_effect(
         %Game{} = game,
         attacking_player_id,
         defender_player_id,
         %{
           self_knocked_out?: true
         }
       ) do
    resolve_replacement_after_knockout(game, defender_player_id, attacking_player_id)
  end

  defp resolve_self_replacement_after_attack_effect(
         %Game{} = game,
         _attacking_player_id,
         _defender_player_id,
         _effect_payload
       ) do
    {:ok, game}
  end

  defp create_knockout_prize_selections(game_id, []) do
    get_game(game_id)
  end

  defp create_knockout_prize_selections(game_id, [selection | queued_selections]) do
    create_knockout_prize_selection(
      game_id,
      selection.player_id,
      selection.prize_records,
      queued_knockout_prize_selection_payloads(queued_selections)
    )
  end

  defp create_knockout_prize_selection(
         game_id,
         attacking_player_id,
         prize_records,
         queued_selections
       )
       when is_list(prize_records) and is_list(queued_selections) do
    prize_count = total_knockout_prize_count(prize_records)
    first_record = List.first(prize_records)
    knocked_out_card_instance_ids = knockout_card_instance_ids(prize_records)
    knocked_out_player_ids = knockout_player_ids(prize_records)
    knockout_payloads = knockout_prize_payloads(prize_records)
    queued_selection_count = length(queued_selections)

    with {:ok, game} <- get_game(game_id),
         :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
         {:ok, prize_cards} <- cards_in_zone(game.id, attacking_player_id, :prize),
         required_prize_count = min(prize_count, length(prize_cards)),
         {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game.id,
             source_type: :knockout_prize,
             controller_player_id: attacking_player_id,
             current_player_id: attacking_player_id,
             effect_key: :choose_knockout_prizes,
             step: "awaiting_choice",
             state: %{
               "version" => 1,
               "kind" => "knockout_prize",
               "player_id" => attacking_player_id,
               "knockouts" => knockout_payloads,
               "knocked_out_card_instance_id" => first_record.knocked_out_card_instance_id,
               "knocked_out_card_instance_ids" => knocked_out_card_instance_ids,
               "knocked_out_player_id" => first_record.knocked_out_player_id,
               "knocked_out_player_ids" => knocked_out_player_ids,
               "prize_count" => prize_count,
               "required_prize_count" => required_prize_count,
               "queued_knockout_prize_selections" => queued_selections,
               "queued_knockout_prize_selection_count" => queued_selection_count
             }
           }),
         {:ok, pending_effect} <-
           update(pending_effect, :await_prompt, %{
             current_player_id: attacking_player_id,
             effect_key: :choose_knockout_prizes,
             step: "awaiting_choice",
             state: pending_effect.state || %{}
           }),
         {:ok, prompt} <-
           create(Prompt, :create, %{
             game_id: game.id,
             turn_id: current_turn_id(game.id),
             pending_effect_id: pending_effect.id,
             prompt_type: "choose_knockout_prizes",
             player_id: attacking_player_id,
             payload: %{
               "choice_key" => "knockout_prize_cards",
               "legal_choices" => Enum.map(prize_cards, & &1.id),
               "legal_choice_labels" => prize_choice_labels(prize_cards),
               "min" => required_prize_count,
               "max" => required_prize_count,
               "knockouts" => knockout_payloads,
               "knocked_out_card_instance_id" => first_record.knocked_out_card_instance_id,
               "knocked_out_card_instance_ids" => knocked_out_card_instance_ids,
               "knocked_out_player_id" => first_record.knocked_out_player_id,
               "knocked_out_player_ids" => knocked_out_player_ids,
               "prize_count" => prize_count,
               "queued_knockout_prize_selection_count" => queued_selection_count
             }
           }),
         {:ok, event} <-
           write_event(game, :knockout_prize_selection_required, attacking_player_id, %{
             turn_id: current_turn_id(game.id),
             prompt_id: prompt.id,
             pending_effect_id: pending_effect.id,
             prize_count: prize_count,
             required_prize_count: required_prize_count,
             knockouts: knockout_payloads,
             knocked_out_card_instance_id: first_record.knocked_out_card_instance_id,
             knocked_out_card_instance_ids: knocked_out_card_instance_ids,
             knocked_out_player_id: first_record.knocked_out_player_id,
             knocked_out_player_ids: knocked_out_player_ids,
             queued_knockout_prize_selection_count: queued_selection_count
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      get_game(game.id)
    end
  end

  defp maybe_create_queued_knockout_prize_selection(
         %Game{status: :finished} = game,
         _pending_effect
       ) do
    {:ok, game}
  end

  defp maybe_create_queued_knockout_prize_selection(
         %Game{} = game,
         %PendingEffect{} = pending_effect
       ) do
    case queued_knockout_prize_selections(pending_effect) do
      [] ->
        {:ok, game}

      [selection_payload | remaining_selection_payloads] ->
        with {:ok, selection} <- decode_queued_knockout_prize_selection(selection_payload) do
          create_knockout_prize_selection(
            game.id,
            selection.player_id,
            selection.prize_records,
            remaining_selection_payloads
          )
        end
    end
  end

  defp stabilize_flow(%Game{status: :finished} = game), do: {:ok, game}

  defp stabilize_flow(%Game{} = game), do: FlowInterpreter.stabilize(game)

  defp total_knockout_prize_count(prize_records) do
    Enum.reduce(prize_records, 0, &(&1.prize_count + &2))
  end

  defp knockout_card_instance_ids(prize_records) do
    Enum.map(prize_records, & &1.knocked_out_card_instance_id)
  end

  defp knockout_player_ids(prize_records) do
    prize_records
    |> Enum.map(& &1.knocked_out_player_id)
    |> Enum.uniq()
  end

  defp knockout_prize_payloads(prize_records) do
    Enum.map(prize_records, fn prize_record ->
      %{
        "knocked_out_card_id" => prize_record.knocked_out_card_id,
        "knocked_out_card_instance_id" => prize_record.knocked_out_card_instance_id,
        "knocked_out_player_id" => prize_record.knocked_out_player_id,
        "prize_count" => prize_record.prize_count
      }
    end)
  end

  defp queued_knockout_prize_selection_payloads(selections) do
    Enum.map(selections, fn selection ->
      %{
        "player_id" => selection.player_id,
        "prize_records" => knockout_prize_payloads(selection.prize_records)
      }
    end)
  end

  defp queued_knockout_prize_selections(%PendingEffect{state: state}) do
    case Map.get(state || %{}, "queued_knockout_prize_selections") do
      queued_selections when is_list(queued_selections) -> queued_selections
      _other -> []
    end
  end

  defp decode_queued_knockout_prize_selection(%{
         "player_id" => player_id,
         "prize_records" => prize_record_payloads
       })
       when is_binary(player_id) and is_list(prize_record_payloads) do
    with {:ok, prize_records} <-
           prize_record_payloads
           |> Enum.map(&decode_queued_knockout_prize_record/1)
           |> collect_results() do
      {:ok, %{player_id: player_id, prize_records: prize_records}}
    end
  end

  defp decode_queued_knockout_prize_selection(_payload) do
    {:error, :invalid_queued_knockout_prize_selection}
  end

  defp decode_queued_knockout_prize_record(%{
         "knocked_out_card_id" => card_id,
         "knocked_out_card_instance_id" => card_instance_id,
         "knocked_out_player_id" => player_id,
         "prize_count" => prize_count
       })
       when is_binary(card_id) and is_binary(card_instance_id) and is_binary(player_id) and
              is_integer(prize_count) and
              prize_count >= 0 do
    {:ok,
     %{
       knocked_out_card_id: card_id,
       knocked_out_card_instance_id: card_instance_id,
       knocked_out_player_id: player_id,
       prize_count: prize_count
     }}
  end

  defp decode_queued_knockout_prize_record(_payload) do
    {:error, :invalid_queued_knockout_prize_record}
  end

  defp current_turn_id(game_id) do
    case current_turn(game_id) do
      {:ok, %Turn{id: turn_id}} -> turn_id
      _other -> nil
    end
  end

  defp prize_choice_labels(prize_cards) do
    Enum.map(prize_cards, fn prize_card ->
      %{
        "id" => prize_card.id,
        "label" => "Prize #{prize_card.position}",
        "detail" => "Face-down Prize card"
      }
    end)
  end

  defp pending_knockout_card_instance_ids(%PendingEffect{state: state}) do
    state = state || %{}

    case Map.get(state, "knocked_out_card_instance_ids") do
      ids when is_list(ids) ->
        Enum.filter(ids, &is_binary/1)

      _other ->
        state
        |> Map.get("knocked_out_card_instance_id")
        |> List.wrap()
        |> Enum.filter(&is_binary/1)
    end
  end

  defp pending_knockout_player_ids(%PendingEffect{state: state}) do
    state = state || %{}

    case Map.get(state, "knocked_out_player_ids") do
      ids when is_list(ids) ->
        Enum.filter(ids, &is_binary/1)

      _other ->
        state |> Map.get("knocked_out_player_id") |> List.wrap() |> Enum.filter(&is_binary/1)
    end
  end

  defp resolve_replacement_after_knockout(
         %Game{status: :finished} = game,
         _attacking_player_id,
         _knocked_out_player_id
       ) do
    {:ok, game}
  end

  defp resolve_replacement_after_knockout(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id
       ) do
    with {:ok, replacement_result} <-
           resolve_replacement_active_after_knockout(game.id, knocked_out_player_id) do
      cond do
        replacement_result.empty_board? ->
          write_empty_board_win(game, attacking_player_id, knocked_out_player_id)

        replacement_result.promoted_card_instance_id ->
          write_auto_replacement_active(game, knocked_out_player_id, replacement_result)

        replacement_result.replacement_required? ->
          write_replacement_required(game, knocked_out_player_id, replacement_result)

        true ->
          {:ok, game}
      end
    end
  end

  defp write_empty_board_win(%Game{} = game, attacking_player_id, knocked_out_player_id) do
    with {:ok, game} <-
           maybe_finish_for_empty_board(game, attacking_player_id, knocked_out_player_id),
         {:ok, event} <-
           write_event(game, :empty_board_win, attacking_player_id, %{
             winner_player_id: game.winner_player_id,
             knocked_out_player_id: knocked_out_player_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      get_game(game.id)
    end
  end

  defp write_auto_replacement_active(%Game{} = game, player_id, replacement_result) do
    with {:ok, event} <-
           write_event(game, :auto_replacement_active, player_id, %{
             bench_card_instance_id: replacement_result.promoted_card_instance_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      get_game(game.id)
    end
  end

  defp write_replacement_required(%Game{} = game, player_id, replacement_result) do
    with {:ok, event} <-
           write_event(game, :replacement_active_required, player_id, %{
             candidate_card_instance_ids:
               replacement_result.replacement_candidate_card_instance_ids
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      get_game(game.id)
    end
  end

  defp move_adrena_brain_damage_counters(
         game_id,
         %CardInstance{} = source_card,
         %CardInstance{} = from_card,
         %CardInstance{} = target_card,
         %Turn{} = turn,
         damage_counters
       ) do
    moved_damage = AbilityEffects.damage_for_counters(damage_counters)
    from_resulting_damage = max(from_card.damage - moved_damage, 0)
    target_resulting_damage = target_card.damage + moved_damage

    with {:ok, _from_card} <-
           update(from_card, :set_damage, %{damage: from_resulting_damage}),
         {:ok, current_source_card} <- get_card(game_id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_adrena_brain_used_marker(current_source_card, turn)
           }),
         {:ok, _target_card} <-
           update(target_card, :set_damage, %{damage: target_resulting_damage}),
         {:ok, knocked_out?} <-
           maybe_knock_out_after_adrena_brain(game_id, target_card, target_resulting_damage) do
      {:ok,
       %{
         damage_counters: damage_counters,
         moved_damage: moved_damage,
         from_starting_damage: from_card.damage,
         from_resulting_damage: from_resulting_damage,
         target_starting_damage: target_card.damage,
         target_resulting_damage: target_resulting_damage,
         knocked_out?: knocked_out?
       }}
    end
  end

  defp maybe_knock_out_after_adrena_brain(game_id, %CardInstance{} = target_card, new_damage) do
    with {:ok, target_hp} <- pokemon_hp(target_card.card_id) do
      if new_damage < target_hp do
        {:ok, false}
      else
        with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, target_card) do
          {:ok, true}
        end
      end
    end
  end

  defp adrena_brain_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         %CardInstance{} = from_card,
         %CardInstance{} = target_card,
         ability_result
       ) do
    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.adrena_brain_ability_id()),
      effect_type: :move_damage_counters,
      from_card_instance_id: from_card.id,
      target_card_instance_id: target_card.id,
      damage_counters: ability_result.damage_counters,
      moved_damage: ability_result.moved_damage,
      from_starting_damage: ability_result.from_starting_damage,
      from_resulting_damage: ability_result.from_resulting_damage,
      target_starting_damage: ability_result.target_starting_damage,
      target_resulting_damage: ability_result.target_resulting_damage,
      knocked_out?: ability_result.knocked_out?,
      public_note: adrena_brain_public_note(ability_result.damage_counters)
    }
  end

  defp resolve_adrena_brain_knockout(
         game_id,
         _attacking_player_id,
         _knocked_out_player_id,
         _target_card,
         %{
           knocked_out?: false
         }
       ) do
    get_game(game_id)
  end

  defp resolve_adrena_brain_knockout(
         game_id,
         attacking_player_id,
         knocked_out_player_id,
         %CardInstance{} = target_card,
         %{knocked_out?: true}
       ) do
    with {:ok, prize_records} <-
           active_knockout_prize_records(game_id, knocked_out_player_id, target_card, %{
             knocked_out?: true
           }),
         {:ok, game} <-
           create_knockout_prize_selections(game_id, [
             %{player_id: attacking_player_id, prize_records: prize_records}
           ]) do
      case target_card.zone do
        :active ->
          resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)

        _bench_or_other ->
          {:ok, game}
      end
    end
  end

  defp draw_team_rockets_factory_cards(game_id, player, draw_count) do
    with {:ok, cards} <- Prizmo.TcgEngine.CardStore.deck_cards_for_player(player.id, draw_count) do
      cards
      |> Enum.map(&move_deck_card_to_hand(game_id, player.player_id, &1))
      |> collect_results()
    end
  end

  defp team_rockets_factory_public_note(player_id, 1) do
    "Team Rocket's Factory let #{String.replace(player_id, "_", " ")} draw 1 card."
  end

  defp team_rockets_factory_public_note(player_id, card_count) do
    "Team Rocket's Factory let #{String.replace(player_id, "_", " ")} draw #{card_count} cards."
  end

  defp adrena_brain_public_note(1), do: "Adrena-Brain moved 1 damage counter."

  defp adrena_brain_public_note(damage_counters) do
    "Adrena-Brain moved #{damage_counters} damage counters."
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attack_damage_payload(damage_result) do
    %{
      damage: damage_result.damage,
      resulting_damage: damage_result.resulting_damage,
      knocked_out?: damage_result.knocked_out?
    }
    |> maybe_put(:damage_prevented?, Map.get(damage_result, :damage_prevented?))
    |> maybe_put(:prevented_damage, Map.get(damage_result, :prevented_damage))
    |> maybe_put(
      :attack_prevention_source_card_id,
      Map.get(damage_result, :attack_prevention_source_card_id)
    )
    |> maybe_put(
      :attack_prevention_source_attack_id,
      Map.get(damage_result, :attack_prevention_source_attack_id)
    )
    |> maybe_put(
      :attack_prevention_source_player_id,
      Map.get(damage_result, :attack_prevention_source_player_id)
    )
    |> maybe_put(
      :attack_prevention_source_turn_number,
      Map.get(damage_result, :attack_prevention_source_turn_number)
    )
    |> maybe_put(
      :attack_prevention_blocked_turn_number,
      Map.get(damage_result, :attack_prevention_blocked_turn_number)
    )
    |> maybe_put(:protected_card_instance_id, Map.get(damage_result, :protected_card_instance_id))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_non_empty(map, _key, []), do: map
  defp maybe_put_non_empty(map, key, value), do: maybe_put(map, key, value)

  defp setup_move_payload(%Setup{} = setup, player_facts) do
    %{
      setup_id: setup.id,
      players: player_facts
    }
  end

  @spec draw_for_turn(Game.t() | String.t(), String.t()) :: {:ok, Game.t()} | {:error, term()}
  def draw_for_turn(game_or_id, player_id) when is_binary(player_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- current_turn(game.id),
           :ok <- require_turn_player(turn, player_id),
           {:ok, turn} <- update(turn, :draw_for_turn, %{}) do
        case draw_one_for_turn(game.id, player_id) do
          {:ok, drawn_card} ->
            with {:ok, event} <-
                   write_event(game, :draw_for_turn, player_id, %{
                     turn_id: turn.id,
                     card: [drawn_card] |> EventPayloads.moved_cards(:deck, :hand) |> List.first()
                   }),
                 {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
              get_game(game.id)
            end

          {:error, :cannot_draw_from_empty_deck} ->
            with {:ok, winner_player_id} <- opponent_player_id(game.id, player_id),
                 {:ok, game} <- update(game, :finish, %{winner_player_id: winner_player_id}),
                 {:ok, event} <-
                   write_event(game, :deck_out, player_id, %{
                     turn_id: turn.id,
                     winner_player_id: winner_player_id
                   }),
                 {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
              get_game(game.id)
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end)
  end

  @spec skip_draw_for_turn(Game.t() | String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def skip_draw_for_turn(game_or_id, player_id) when is_binary(player_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- current_turn(game.id),
           :ok <- require_turn_player(turn, player_id),
           {:ok, turn} <- update(turn, :skip_draw_for_turn, %{}),
           {:ok, event} <- write_event(game, :skip_draw_for_turn, player_id, %{turn_id: turn.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec open_action_window(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def open_action_window(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           {:ok, turn} <- current_turn(game.id),
           {:ok, turn} <- update(turn, :open_action_window, %{}),
           {:ok, event} <-
             write_event(game, :open_action_window, turn.active_player_id, %{turn_id: turn.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec end_turn(Game.t() | String.t(), String.t()) :: {:ok, Game.t()} | {:error, term()}
  def end_turn(game_or_id, player_id) when is_binary(player_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           :ok <- require_game_status(game, :in_progress),
           :ok <- require_active_player(game, player_id),
           {:ok, turn} <- current_turn(game.id),
           :ok <- require_turn_player(turn, player_id),
           {:ok, turn} <- update(turn, :end_turn, %{}),
           {:ok, event} <- write_event(game, :end_turn, player_id, %{turn_id: turn.id}),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        get_game(game.id)
      end
    end)
  end

  @spec undo(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def undo(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           true <- game.cursor_index > 0 || {:error, :nothing_to_undo} do
        SnapshotRestorer.restore(game.id, game.cursor_index - 1)
      end
    end)
  end

  @spec redo(Game.t() | String.t()) :: {:ok, Game.t()} | {:error, term()}
  def redo(game_or_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           true <- game.cursor_index < game.latest_event_index || {:error, :nothing_to_redo} do
        SnapshotRestorer.restore(game.id, game.cursor_index + 1)
      end
    end)
  end
end
