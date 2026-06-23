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
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.ChoiceValidator
  alias Prizmo.TcgEngine.EnergyEffects
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Flow.Interpreter, as: FlowInterpreter
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameSetup
  alias Prizmo.TcgEngine.HpEffects
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
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
           :ok <- maybe_trigger_last_ditch_catch(game, turn, updated_card) do
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
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
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
             EnergyEffects.after_attach_from_hand(game, turn, player, energy_card, target_card),
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
           :ok <- require_ace_spec_available(player, metadata, game.id),
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

  @spec resolve_hp_state_based_knockouts(Game.t() | String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def resolve_hp_state_based_knockouts(game_or_id) do
    with {:ok, game} <- get_game(game_or_id) do
      targets = hp_state_based_knockout_targets(game.id)
      resolve_hp_state_based_knockout_targets(game, targets)
    end
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
         %PendingEffect{source_type: :energy_effect} = pending_effect,
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
      EnergyEffects.resume_pending_effect(
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
         %PendingEffect{source_type: :ability_effect} = pending_effect,
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
      AbilityEffects.resume_pending_effect(
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
           :ok <- require_ace_spec_available(player, metadata, game.id),
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
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
           {:ok, _game} <- resolve_hp_state_based_knockouts(game.id) do
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
           {:ok, drawn_cards} <- draw_cards_from_deck(game.id, player, draw_count),
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

  @spec use_cursed_blast(
          Game.t() | String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, Game.t()} | {:error, term()}
  def use_cursed_blast(game_or_id, player_id, source_card_instance_id, target_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           {:ok, opponent_player_id} <- opponent_player_id(game.id, player_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_cursed_blast_available(game.id, source_card, turn),
           :ok <- require_card_owned_by_player(target_card, opponent_player_id),
           :ok <- require_in_play_pokemon_zone(target_card),
           {:ok, ability_result} <-
             resolve_cursed_blast(game.id, player_id, source_card, target_card, turn),
           {:ok, event} <-
             write_event(
               game,
               :ability_used,
               player_id,
               cursed_blast_event_payload(turn, source_card, target_card, ability_result)
             ),
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
        resolve_cursed_blast_knockouts(
          game.id,
          player_id,
          opponent_player_id,
          source_card,
          target_card,
          ability_result
        )
      end
    end)
  end

  @spec use_teal_mask_ogerpon_teal_dance(
          Game.t() | String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, Game.t()} | {:error, term()}
  def use_teal_mask_ogerpon_teal_dance(
        game_or_id,
        player_id,
        source_card_instance_id,
        energy_card_instance_id
      )
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(energy_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           {:ok, energy_card} <- get_card(game.id, energy_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_teal_dance_available(game.id, source_card, turn),
           :ok <- require_card_owned_by_player(energy_card, player_id),
           :ok <- require_card_zone(energy_card, :hand),
           :ok <- AbilityEffects.require_basic_grass_energy(energy_card),
           {:ok, ability_result} <-
             attach_teal_dance_energy_and_draw(game, player, source_card, energy_card, turn),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               teal_dance_event_payload(turn, source_card, energy_card, ability_result)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_blaziken_ex_seething_spirit(
          Game.t() | String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, Game.t()} | {:error, term()}
  def use_blaziken_ex_seething_spirit(
        game_or_id,
        player_id,
        source_card_instance_id,
        energy_card_instance_id,
        target_card_instance_id
      )
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(energy_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           {:ok, energy_card} <- get_card(game.id, energy_card_instance_id),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_seething_spirit_available(game.id, source_card, turn),
           :ok <- require_card_owned_by_player(energy_card, player_id),
           :ok <- require_card_zone(energy_card, :discard),
           :ok <- AbilityEffects.require_basic_energy(energy_card),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_in_play_pokemon_zone(target_card),
           {:ok, ability_result} <-
             attach_seething_spirit_energy(game, source_card, energy_card, target_card, turn),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               seething_spirit_event_payload(
                 turn,
                 source_card,
                 energy_card,
                 target_card,
                 ability_result
               )
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_fezandipiti_flip_the_script(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_fezandipiti_flip_the_script(game_or_id, player_id, source_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_flip_the_script_available(game.id, source_card, turn),
           {:ok, ability_result} <- draw_flip_the_script_cards(game, player, source_card, turn),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               flip_the_script_event_payload(turn, source_card, ability_result)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_psychic_draw(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_psychic_draw(game_or_id, player_id, source_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_psychic_draw_available(source_card, turn),
           {:ok, ability_result} <- draw_psychic_draw_cards(game, player, source_card, turn),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               psychic_draw_event_payload(turn, source_card, ability_result)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_noctowl_jewel_seeker(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_noctowl_jewel_seeker(game_or_id, player_id, source_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, _player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_jewel_seeker_available(game.id, source_card, turn),
           {:ok, max_targets} <- AbilityEffects.jewel_seeker_max_targets(source_card),
           {:ok, deck_cards} <- cards_in_zone(game.id, player_id, :deck),
           legal_choice_cards = AbilityEffects.jewel_seeker_legal_choice_cards(deck_cards),
           legal_choice_ids = Enum.map(legal_choice_cards, & &1.id),
           {:ok, current_source_card} <- get_card(game.id, source_card.id),
           {:ok, marked_source_card} <-
             update(current_source_card, :set_markers, %{
               markers: AbilityEffects.put_jewel_seeker_used_marker(current_source_card, turn)
             }),
           {:ok, pending_effect} <-
             create(PendingEffect, :create, %{
               game_id: game.id,
               source_type: :ability_effect,
               source_card_instance_id: marked_source_card.id,
               source_card_id: marked_source_card.card_id,
               controller_player_id: player_id,
               current_player_id: player_id,
               effect_key: AbilityEffects.jewel_seeker_ability_id(),
               step: "awaiting_choice",
               state: %{
                 "version" => 1,
                 "kind" => "ability_effect",
                 "effect_type" => Atom.to_string(AbilityEffects.jewel_seeker_ability_id()),
                 "player_id" => player_id,
                 "source_card_instance_id" => marked_source_card.id,
                 "source_card_id" => marked_source_card.card_id,
                 "legal_choice_ids" => legal_choice_ids
               }
             }),
           {:ok, pending_effect} <-
             update(pending_effect, :await_prompt, %{
               current_player_id: player_id,
               effect_key: AbilityEffects.jewel_seeker_ability_id(),
               step: "awaiting_choice",
               state: pending_effect.state || %{}
             }),
           {:ok, _prompt} <-
             create(Prompt, :create, %{
               game_id: game.id,
               turn_id: turn.id,
               pending_effect_id: pending_effect.id,
               prompt_type: "select_cards",
               player_id: player_id,
               payload: %{
                 "choice_key" => Atom.to_string(AbilityEffects.jewel_seeker_ability_id()),
                 "legal_choices" => legal_choice_ids,
                 "legal_choice_labels" =>
                   AbilityEffects.jewel_seeker_choice_labels(legal_choice_cards),
                 "min" => 0,
                 "max" => max_targets,
                 "source_card_instance_id" => marked_source_card.id,
                 "source_card_id" => marked_source_card.card_id
               }
             }),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               jewel_seeker_event_payload(turn, marked_source_card)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_drakloak_recon_directive(Game.t() | String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_drakloak_recon_directive(
        game_or_id,
        player_id,
        source_card_instance_id,
        chosen_card_instance_id
      )
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(chosen_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           {:ok, top_cards} <- CardStore.deck_cards_for_player(player.id, 2),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_recon_directive_available(source_card, top_cards, turn),
           {:ok, chosen_card} <- require_top_deck_choice(top_cards, chosen_card_instance_id),
           other_cards = Enum.reject(top_cards, &(&1.id == chosen_card.id)),
           {:ok, ability_result} <-
             resolve_recon_directive_choice(
               game,
               player,
               source_card,
               chosen_card,
               other_cards,
               turn
             ),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               recon_directive_event_payload(turn, source_card, ability_result)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_dudunsparce_run_away_draw(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_dudunsparce_run_away_draw(game_or_id, player_id, source_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_run_away_draw_available(source_card, turn),
           {:ok, ability_result} <-
             draw_and_shuffle_run_away_draw(game, player, source_card, turn),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               run_away_draw_event_payload(turn, source_card, ability_result)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_fan_rotom_fan_call(Game.t() | String.t(), String.t(), String.t()) ::
          {:ok, Game.t()} | {:error, term()}
  def use_fan_rotom_fan_call(game_or_id, player_id, source_card_instance_id)
      when is_binary(player_id) and is_binary(source_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, _player} <- get_player(game.id, player_id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_fan_call_available(source_card, turn),
           {:ok, deck_cards} <- cards_in_zone(game.id, player_id, :deck),
           legal_choice_cards = fan_call_legal_choice_cards(deck_cards),
           legal_choice_ids = Enum.map(legal_choice_cards, & &1.id),
           {:ok, current_source_card} <- get_card(game.id, source_card.id),
           {:ok, marked_source_card} <-
             update(current_source_card, :set_markers, %{
               markers: AbilityEffects.put_fan_call_used_marker(current_source_card, turn)
             }),
           {:ok, pending_effect} <-
             create(PendingEffect, :create, %{
               game_id: game.id,
               source_type: :ability_effect,
               source_card_instance_id: marked_source_card.id,
               source_card_id: marked_source_card.card_id,
               controller_player_id: player_id,
               current_player_id: player_id,
               effect_key: AbilityEffects.fan_call_ability_id(),
               step: "awaiting_choice",
               state: %{
                 "version" => 1,
                 "kind" => "ability_effect",
                 "effect_type" => Atom.to_string(AbilityEffects.fan_call_ability_id()),
                 "player_id" => player_id,
                 "source_card_instance_id" => marked_source_card.id,
                 "source_card_id" => marked_source_card.card_id,
                 "legal_choice_ids" => legal_choice_ids
               }
             }),
           {:ok, pending_effect} <-
             update(pending_effect, :await_prompt, %{
               current_player_id: player_id,
               effect_key: AbilityEffects.fan_call_ability_id(),
               step: "awaiting_choice",
               state: pending_effect.state || %{}
             }),
           {:ok, _prompt} <-
             create(Prompt, :create, %{
               game_id: game.id,
               turn_id: turn.id,
               pending_effect_id: pending_effect.id,
               prompt_type: "select_cards",
               player_id: player_id,
               payload: %{
                 "choice_key" => Atom.to_string(AbilityEffects.fan_call_ability_id()),
                 "legal_choices" => legal_choice_ids,
                 "legal_choice_labels" => fan_call_choice_labels(legal_choice_cards),
                 "min" => 0,
                 "max" => 3,
                 "source_card_instance_id" => marked_source_card.id,
                 "source_card_id" => marked_source_card.card_id
               }
             }),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               fan_call_event_payload(turn, marked_source_card)
             ) do
        get_game(game.id)
      end
    end)
  end

  @spec use_pecharunt_ex_subjugating_chains(
          Game.t() | String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, Game.t()} | {:error, term()}
  def use_pecharunt_ex_subjugating_chains(
        game_or_id,
        player_id,
        source_card_instance_id,
        target_card_instance_id
      )
      when is_binary(player_id) and is_binary(source_card_instance_id) and
             is_binary(target_card_instance_id) do
    transaction(fn ->
      with {:ok, game} <- get_game(game_or_id),
           {:ok, turn} <- require_action_window_for_player(game, player_id),
           :ok <- CardPlay.require_no_awaiting_pending_effect(game.id),
           {:ok, source_card} <- get_card(game.id, source_card_instance_id),
           :ok <- require_card_owned_by_player(source_card, player_id),
           :ok <- AbilityEffects.require_subjugating_chains_available(game.id, source_card, turn),
           {:ok, target_card} <- get_card(game.id, target_card_instance_id),
           :ok <- require_card_owned_by_player(target_card, player_id),
           :ok <- require_card_zone(target_card, :bench),
           :ok <- AbilityEffects.require_subjugating_chains_target(target_card),
           {:ok, current_source_card} <- get_card(game.id, source_card.id),
           {:ok, marked_source_card} <-
             update(current_source_card, :set_markers, %{
               markers:
                 AbilityEffects.put_subjugating_chains_used_marker(current_source_card, turn)
             }),
           {:ok, active_card} <- active_card(game.id, player_id),
           bench_position = target_card.position,
           {:ok, _active_card} <-
             update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
           {:ok, promoted_card} <-
             update(target_card, :promote_to_active, %{position: 1, status: nil}),
           {:ok, poison_result} <- maybe_set_pokemon_status(game.id, promoted_card, :poisoned),
           {:ok, _event} <-
             write_event_and_snapshot(
               game.id,
               :ability_used,
               player_id,
               subjugating_chains_event_payload(
                 turn,
                 marked_source_card,
                 active_card,
                 promoted_card,
                 poison_result
               )
             ) do
        get_game(game.id)
      end
    end)
  end

  defp fan_call_legal_choice_cards(deck_cards) do
    deck_cards
    |> Enum.filter(fn card ->
      case CardCatalog.fetch(card.card_id) do
        {:ok, %{supertype: :pokemon, types: types}} when is_list(types) ->
          :colorless in types

        {:ok, %{supertype: :pokemon, type: :colorless}} ->
          true

        _ ->
          false
      end
    end)
    |> Enum.filter(fn card ->
      case pokemon_hp(card.card_id) do
        {:ok, hp} -> hp <= 100
        _ -> false
      end
    end)
  end

  defp fan_call_choice_labels(cards) do
    Enum.map(cards, fn card ->
      case CardCatalog.fetch(card.card_id) do
        {:ok, %{name: name}} -> name
        _ -> card.card_id
      end
    end)
  end

  defp fan_call_event_payload(%Turn{} = turn, %CardInstance{} = source_card) do
    %{
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number,
      "player_id" => source_card.owner_player_id,
      "ability_id" => Atom.to_string(AbilityEffects.fan_call_ability_id()),
      "source_card_id" => source_card.id,
      "source_card_card_id" => source_card.card_id,
      "message" => "Fan Rotom used Fan Call."
    }
  end

  defp subjugating_chains_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         %CardInstance{} = active_card,
         %CardInstance{} = promoted_card,
         poison_result
       )
       when is_map(poison_result) do
    %{
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number,
      "player_id" => source_card.owner_player_id,
      "ability_id" => Atom.to_string(AbilityEffects.subjugating_chains_ability_id()),
      "source_card_id" => source_card.card_id,
      "source_card_instance_id" => source_card.id,
      "active_card_instance_id" => active_card.id,
      "bench_card_instance_id" => promoted_card.id,
      "status" => "poisoned",
      "status_applied" => Map.get(poison_result, :status_applied?, false),
      "public_note" => subjugating_chains_public_note(poison_result)
    }
  end

  defp jewel_seeker_event_payload(%Turn{} = turn, %CardInstance{} = source_card) do
    %{
      "turn_id" => turn.id,
      "turn_number" => turn.turn_number,
      "player_id" => source_card.owner_player_id,
      "ability_id" => Atom.to_string(AbilityEffects.jewel_seeker_ability_id()),
      "source_card_id" => source_card.card_id,
      "source_card_instance_id" => source_card.id,
      "public_note" => "Noctowl used Jewel Seeker."
    }
  end

  defp maybe_trigger_last_ditch_catch(
         %Game{} = game,
         %Turn{} = turn,
         %CardInstance{} = source_card
       ) do
    if AbilityEffects.last_ditch_catch_source?(source_card) do
      with :ok <- AbilityEffects.require_last_ditch_catch_available(game.id, source_card, turn),
           {:ok, deck_cards} <- cards_in_zone(game.id, source_card.owner_player_id, :deck) do
        legal_choice_cards = AbilityEffects.last_ditch_catch_legal_choice_cards(deck_cards)

        case legal_choice_cards do
          [] ->
            :ok

          _cards ->
            legal_choice_ids = Enum.map(legal_choice_cards, & &1.id)

            with {:ok, pending_effect} <-
                   create(PendingEffect, :create, %{
                     game_id: game.id,
                     source_type: :ability_effect,
                     source_card_instance_id: source_card.id,
                     source_card_id: source_card.card_id,
                     controller_player_id: source_card.owner_player_id,
                     current_player_id: source_card.owner_player_id,
                     effect_key: AbilityEffects.last_ditch_catch_ability_id(),
                     step: "awaiting_choice",
                     state: %{
                       "version" => 1,
                       "kind" => "ability_effect",
                       "effect_type" =>
                         Atom.to_string(AbilityEffects.last_ditch_catch_ability_id()),
                       "player_id" => source_card.owner_player_id,
                       "source_card_instance_id" => source_card.id,
                       "source_card_id" => source_card.card_id,
                       "legal_choice_ids" => legal_choice_ids
                     }
                   }),
                 {:ok, pending_effect} <-
                   update(pending_effect, :await_prompt, %{
                     current_player_id: source_card.owner_player_id,
                     effect_key: AbilityEffects.last_ditch_catch_ability_id(),
                     step: "awaiting_choice",
                     state: pending_effect.state || %{}
                   }),
                 {:ok, prompt} <-
                   create(Prompt, :create, %{
                     game_id: game.id,
                     turn_id: turn.id,
                     pending_effect_id: pending_effect.id,
                     prompt_type: "select_cards",
                     player_id: source_card.owner_player_id,
                     payload: %{
                       "choice_key" =>
                         Atom.to_string(AbilityEffects.last_ditch_catch_ability_id()),
                       "legal_choices" => legal_choice_ids,
                       "legal_choice_labels" =>
                         AbilityEffects.last_ditch_catch_choice_labels(legal_choice_cards),
                       "min" => 0,
                       "max" => 1,
                       "source_card_instance_id" => source_card.id,
                       "source_card_id" => source_card.card_id
                     }
                   }),
                 {:ok, _event} <-
                   write_event_and_snapshot(
                     game.id,
                     :prompt_created,
                     source_card.owner_player_id,
                     %{
                       prompt_id: prompt.id,
                       pending_effect_id: pending_effect.id,
                       choice_key: AbilityEffects.last_ditch_catch_ability_id(),
                       prompt_type: :select_cards
                     }
                   ) do
              :ok
            end
        end
      else
        {:error, {:ability_already_used_this_turn, _player_id, :last_ditch}} -> :ok
        {:error, {:unsupported_ability_effect, _card_id, _ability_id, _effect_type}} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
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
           :ok <- require_ace_spec_available(player, metadata, game.id),
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
           :ok <- require_evolution_allowed_this_turn(game, turn),
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
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
           {:ok, _game} <- resolve_hp_state_based_knockouts(game.id) do
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
           {:ok, _luxray_payload} <-
             ToolEffects.apply_luxray_draw_if_needed(
               game.id,
               player_id,
               attacker_card,
               defender_card,
               damage_result
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
           {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
           {:ok, game} <- maybe_advance_attack_flow_state(game) do
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
               resolve_active_replacement_after_attack(
                 game,
                 player_id,
                 defender_card.owner_player_id,
                 defender_card,
                 damage_result,
                 effect_payload
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

  defp maybe_advance_attack_flow_state(%Game{flow_state: :turn_attack_declared} = game) do
    update(game, :set_flow_state, %{flow_state: :turn_attack_resolving})
  end

  defp maybe_advance_attack_flow_state(%Game{} = game), do: {:ok, game}

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

  defp resolve_active_replacement_after_attack(
         %Game{status: :finished} = game,
         _attacking_player_id,
         _knocked_out_player_id,
         _defender_card,
         _damage_result,
         _effect_payload
       ) do
    {:ok, game}
  end

  defp resolve_active_replacement_after_attack(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id,
         _defender_card,
         %{knocked_out?: true},
         _effect_payload
       ) do
    resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
  end

  defp resolve_active_replacement_after_attack(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id,
         %CardInstance{} = defender_card,
         _damage_result,
         effect_payload
       ) do
    if defender_card.id in effect_knockout_card_instance_ids(effect_payload) do
      resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
    else
      {:ok, game}
    end
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
         {:ok, effect_records} <- effect_knockout_prize_records(game_id, effect_payload) do
      {:ok, dedupe_knockout_prize_records(active_records ++ effect_records)}
    end
  end

  defp active_knockout_prize_records(
         game_id,
         knocked_out_player_id,
         target_card,
         %{knocked_out?: true} = damage_result
       ) do
    with {:ok, current_target_card} <- get_card(game_id, target_card.id),
         :ok <- require_card_zone(current_target_card, :discard),
         {:ok, prize_record} <-
           knockout_prize_record(
             knocked_out_player_id,
             current_target_card,
             prize_count: Map.get(damage_result, :knockout_prize_count)
           ) do
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

  defp effect_knockout_prize_records(
         game_id,
         %{bench_knocked_out?: true, bench_damage_target_card_instance_id: card_instance_id} =
           effect_payload
       )
       when is_binary(card_instance_id) do
    with {:ok, target_card} <- get_card(game_id, card_instance_id),
         :ok <- require_card_zone(target_card, :discard),
         {:ok, prize_record} <-
           knockout_prize_record(
             target_card.owner_player_id,
             target_card,
             prize_count: Map.get(effect_payload, :bench_knockout_prize_count)
           ) do
      {:ok, [prize_record]}
    end
  end

  defp effect_knockout_prize_records(game_id, effect_payload) do
    effect_payload
    |> effect_knockout_card_instance_ids()
    |> Enum.map(fn bench_card_instance_id ->
      with {:ok, target_card} <- get_card(game_id, bench_card_instance_id),
           :ok <- require_card_zone(target_card, :discard) do
        knockout_prize_record(target_card.owner_player_id, target_card)
      end
    end)
    |> collect_results()
  end

  defp dedupe_knockout_prize_records(prize_records) do
    Enum.uniq_by(prize_records, & &1.knocked_out_card_instance_id)
  end

  defp knockout_prize_record(knocked_out_player_id, target_card, opts \\ []) do
    with {:ok, prize_count} <- knockout_prize_count_from_opts(target_card, opts) do
      {:ok,
       %{
         knocked_out_card_id: target_card.card_id,
         knocked_out_card_instance_id: target_card.id,
         knocked_out_player_id: knocked_out_player_id,
         prize_count: prize_count
       }}
    end
  end

  defp knockout_prize_count_from_opts(target_card, opts) when is_list(opts) do
    case Keyword.get(opts, :prize_count) do
      prize_count when is_integer(prize_count) and prize_count >= 0 ->
        {:ok, prize_count}

      _other ->
        knockout_prize_count(target_card)
    end
  end

  defp effect_knockout_card_instance_ids(%{effect_knockout_card_instance_ids: ids})
       when is_list(ids) do
    ids
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp effect_knockout_card_instance_ids(%{bench_knocked_out?: true} = effect_payload) do
    case Map.get(effect_payload, :bench_damage_target_card_instance_id) do
      card_instance_id when is_binary(card_instance_id) -> [card_instance_id]
      _missing -> []
    end
  end

  defp effect_knockout_card_instance_ids(%{bench_damage_counter_allocations: allocations})
       when is_list(allocations) do
    allocations
    |> Enum.filter(&Map.get(&1, :knocked_out?, false))
    |> Enum.map(&Map.get(&1, :card_instance_id))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp effect_knockout_card_instance_ids(_effect_payload), do: []

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
    with {:ok, knocked_out?} <- HpEffects.damage_knocks_out?(game_id, target_card, new_damage) do
      if knocked_out? do
        with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, target_card) do
          {:ok, true}
        end
      else
        {:ok, false}
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

  defp resolve_cursed_blast(
         game_id,
         player_id,
         %CardInstance{} = source_card,
         %CardInstance{} = target_card,
         %Turn{} = turn
       ) do
    with {:ok, damage_counters} <- AbilityEffects.cursed_blast_counters(source_card),
         damage = AbilityEffects.damage_for_counters(damage_counters),
         {:ok, target_result} <-
           place_cursed_blast_damage_counters(game_id, player_id, target_card, damage_counters),
         {:ok, current_source_card} <- get_card(game_id, source_card.id),
         {:ok, marked_source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_cursed_blast_used_marker(current_source_card, turn)
           }),
         {:ok, self_knocked_out_cards} <- discard_knocked_out_stack(game_id, marked_source_card) do
      {:ok,
       Map.merge(target_result, %{
         damage_counters: damage_counters,
         placed_damage: damage,
         self_knocked_out?: true,
         self_knocked_out_card_instance_ids: Enum.map(self_knocked_out_cards, & &1.id)
       })}
    end
  end

  defp place_cursed_blast_damage_counters(
         game_id,
         player_id,
         %CardInstance{} = target_card,
         damage_counters
       ) do
    damage = AbilityEffects.damage_for_counters(damage_counters)

    case StadiumEffects.damage_counter_prevention_payload(
           game_id,
           target_card,
           player_id,
           :opponent_pokemon_effect
         ) do
      {:prevented, prevention_payload} ->
        {:ok,
         Map.merge(
           %{
             target_starting_damage: target_card.damage,
             target_resulting_damage: target_card.damage,
             target_knocked_out?: false,
             damage_counter_prevented?: true,
             prevented_damage_counters: damage_counters,
             prevented_damage: damage
           },
           prevention_payload
         )}

      :not_prevented ->
        target_resulting_damage = target_card.damage + damage

        with {:ok, _target_card} <-
               update(target_card, :set_damage, %{damage: target_resulting_damage}),
             {:ok, target_knocked_out?} <-
               maybe_knock_out_after_cursed_blast(game_id, target_card, target_resulting_damage) do
          {:ok,
           %{
             target_starting_damage: target_card.damage,
             target_resulting_damage: target_resulting_damage,
             target_knocked_out?: target_knocked_out?,
             damage_counter_prevented?: false,
             prevented_damage_counters: 0,
             prevented_damage: 0
           }}
        end
    end
  end

  defp maybe_knock_out_after_cursed_blast(game_id, %CardInstance{} = target_card, new_damage) do
    with {:ok, knocked_out?} <- HpEffects.damage_knocks_out?(game_id, target_card, new_damage) do
      if knocked_out? do
        with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, target_card) do
          {:ok, true}
        end
      else
        {:ok, false}
      end
    end
  end

  defp hp_state_based_knockout_targets(game_id) when is_binary(game_id) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} ->
        cards
        |> Enum.filter(&(&1.zone in [:active, :bench]))
        |> Enum.reduce([], fn card, targets ->
          case HpEffects.damage_knocks_out?(game_id, card, card.damage || 0) do
            {:ok, true} -> [%{card: card, original_zone: card.zone} | targets]
            _other -> targets
          end
        end)
        |> Enum.reverse()

      {:error, _reason} ->
        []
    end
  end

  defp resolve_hp_state_based_knockout_targets(%Game{} = game, []), do: {:ok, game}

  defp resolve_hp_state_based_knockout_targets(%Game{} = game, targets) do
    with {:ok, discarded_targets} <- discard_hp_state_based_knockout_targets(game.id, targets),
         {:ok, prize_selections} <- hp_state_based_prize_selections(game.id, discarded_targets),
         {:ok, game} <- create_knockout_prize_selections(game.id, prize_selections) do
      resolve_hp_state_based_replacements(game, discarded_targets)
    end
  end

  defp discard_hp_state_based_knockout_targets(game_id, targets) when is_list(targets) do
    targets
    |> Enum.map(fn %{card: card} = target ->
      with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, card),
           {:ok, discarded_card} <- get_card(game_id, card.id) do
        {:ok, Map.put(target, :discarded_card, discarded_card)}
      end
    end)
    |> collect_results()
  end

  defp hp_state_based_prize_selections(game_id, targets) when is_list(targets) do
    Enum.reduce_while(targets, {:ok, []}, fn %{discarded_card: discarded_card},
                                             {:ok, selections} ->
      with {:ok, attacking_player_id} <-
             opponent_player_id(game_id, discarded_card.owner_player_id),
           {:ok, prize_record} <-
             knockout_prize_record(discarded_card.owner_player_id, discarded_card) do
        {:cont,
         {:ok, append_knockout_prize_selection(selections, attacking_player_id, [prize_record])}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_hp_state_based_replacements(%Game{} = game, targets) when is_list(targets) do
    targets
    |> Enum.filter(&(&1.original_zone == :active))
    |> Enum.map(& &1.card.owner_player_id)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, game}, fn knocked_out_player_id, {:ok, current_game} ->
      with {:ok, attacking_player_id} <-
             opponent_player_id(current_game.id, knocked_out_player_id),
           {:ok, next_game} <-
             resolve_replacement_after_knockout(
               current_game,
               attacking_player_id,
               knocked_out_player_id
             ) do
        {:cont, {:ok, next_game}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp cursed_blast_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         %CardInstance{} = target_card,
         ability_result
       ) do
    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.cursed_blast_ability_id()),
      effect_type: :damage_counters_to_opponent_pokemon_then_self_knock_out,
      target_card_instance_id: target_card.id,
      damage_counters: ability_result.damage_counters,
      placed_damage: ability_result.placed_damage,
      target_starting_damage: ability_result.target_starting_damage,
      target_resulting_damage: ability_result.target_resulting_damage,
      target_knocked_out?: ability_result.target_knocked_out?,
      damage_counter_prevented?: ability_result.damage_counter_prevented?,
      prevented_damage_counters: ability_result.prevented_damage_counters,
      prevented_damage: ability_result.prevented_damage,
      protected_card_instance_id: Map.get(ability_result, :protected_card_instance_id),
      damage_counter_prevention_source_card_id:
        Map.get(ability_result, :damage_counter_prevention_source_card_id),
      damage_counter_prevention_source_card_instance_id:
        Map.get(ability_result, :damage_counter_prevention_source_card_instance_id),
      damage_counter_prevention_source_effect_id:
        Map.get(ability_result, :damage_counter_prevention_source_effect_id),
      self_knocked_out?: ability_result.self_knocked_out?,
      self_knocked_out_card_instance_ids: ability_result.self_knocked_out_card_instance_ids,
      public_note: cursed_blast_public_note(source_card, ability_result.damage_counters)
    }
  end

  defp resolve_cursed_blast_knockouts(
         game_id,
         player_id,
         opponent_player_id,
         %CardInstance{} = source_card,
         %CardInstance{} = target_card,
         ability_result
       ) do
    with {:ok, target_records} <-
           cursed_blast_target_prize_records(
             game_id,
             target_card.owner_player_id,
             target_card,
             ability_result
           ),
         {:ok, self_records} <-
           self_knockout_prize_records(game_id, source_card.owner_player_id, source_card, %{
             self_knocked_out?: true
           }),
         prize_selections =
           []
           |> append_knockout_prize_selection(player_id, target_records)
           |> append_knockout_prize_selection(opponent_player_id, self_records),
         {:ok, game} <- create_knockout_prize_selections(game_id, prize_selections),
         {:ok, game} <-
           maybe_resolve_cursed_blast_target_replacement(
             game,
             player_id,
             target_card.owner_player_id,
             target_card,
             ability_result
           ) do
      maybe_resolve_cursed_blast_self_replacement(
        game,
        opponent_player_id,
        source_card.owner_player_id,
        source_card,
        ability_result
      )
    end
  end

  defp cursed_blast_target_prize_records(game_id, knocked_out_player_id, target_card, %{
         target_knocked_out?: true
       }) do
    with {:ok, current_target_card} <- get_card(game_id, target_card.id),
         :ok <- require_card_zone(current_target_card, :discard),
         {:ok, prize_record} <- knockout_prize_record(knocked_out_player_id, current_target_card) do
      {:ok, [prize_record]}
    end
  end

  defp cursed_blast_target_prize_records(_game_id, _knocked_out_player_id, _target_card, _result) do
    {:ok, []}
  end

  defp maybe_resolve_cursed_blast_target_replacement(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id,
         %CardInstance{zone: :active},
         %{target_knocked_out?: true}
       ) do
    resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
  end

  defp maybe_resolve_cursed_blast_target_replacement(
         %Game{} = game,
         _attacking_player_id,
         _knocked_out_player_id,
         %CardInstance{},
         _ability_result
       ) do
    {:ok, game}
  end

  defp maybe_resolve_cursed_blast_self_replacement(
         %Game{} = game,
         attacking_player_id,
         knocked_out_player_id,
         %CardInstance{zone: :active},
         %{self_knocked_out?: true}
       ) do
    resolve_replacement_after_knockout(game, attacking_player_id, knocked_out_player_id)
  end

  defp maybe_resolve_cursed_blast_self_replacement(
         %Game{} = game,
         _attacking_player_id,
         _knocked_out_player_id,
         %CardInstance{},
         _ability_result
       ) do
    {:ok, game}
  end

  defp cursed_blast_public_note(%CardInstance{card_id: "PRE-037"}, damage_counters) do
    "Dusknoir's Cursed Blast placed #{damage_counters} damage counters, then Dusknoir was Knocked Out."
  end

  defp cursed_blast_public_note(%CardInstance{}, damage_counters) do
    "Dusclops's Cursed Blast placed #{damage_counters} damage counters, then Dusclops was Knocked Out."
  end

  defp attach_teal_dance_energy_and_draw(
         %Game{} = game,
         player,
         %CardInstance{} = source_card,
         %CardInstance{} = energy_card,
         %Turn{} = turn
       ) do
    with {:ok, position} <- next_attachment_position(game.id, source_card.id),
         {:ok, attached_energy} <-
           update(energy_card, :attach, %{
             attached_to_card_instance_id: source_card.id,
             position: position
           }),
         {:ok, recovered_special_condition} <-
           StadiumEffects.recover_special_condition(game.id, source_card),
         {:ok, drawn_cards} <-
           draw_cards_from_deck(game.id, player, AbilityEffects.teal_dance_draw_count()),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_teal_dance_used_marker(current_source_card, turn)
           }) do
      {:ok,
       %{
         attached_energy: attached_energy,
         attached_position: position,
         drawn_cards: drawn_cards,
         recovered_special_condition: recovered_special_condition
       }}
    end
  end

  def attach_energy_from_discard(
        game_id,
        %CardInstance{} = energy_card,
        %CardInstance{} = target_card
      ) do
    with {:ok, game} <- get_game(game_id),
         {:ok, position} <- next_attachment_position(game.id, target_card.id) do
      update(energy_card, :attach_from_discard, %{
        attached_to_card_instance_id: target_card.id,
        position: position
      })
    end
  end

  defp attach_seething_spirit_energy(
         %Game{} = game,
         %CardInstance{} = source_card,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         %Turn{} = turn
       ) do
    with {:ok, position} <- next_attachment_position(game.id, target_card.id),
         {:ok, attached_energy} <-
           update(energy_card, :attach_from_discard, %{
             attached_to_card_instance_id: target_card.id,
             position: position
           }),
         {:ok, recovered_special_condition} <-
           StadiumEffects.recover_special_condition(game.id, target_card),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_seething_spirit_used_marker(current_source_card, turn)
           }) do
      {:ok,
       %{
         attached_energy: attached_energy,
         attached_position: position,
         recovered_special_condition: recovered_special_condition
       }}
    end
  end

  defp draw_flip_the_script_cards(
         %Game{} = game,
         player,
         %CardInstance{} = source_card,
         %Turn{} = turn
       ) do
    with {:ok, drawn_cards} <-
           draw_cards_from_deck(game.id, player, AbilityEffects.flip_the_script_draw_count()),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_flip_the_script_used_marker(current_source_card, turn)
           }) do
      {:ok, %{drawn_cards: drawn_cards}}
    end
  end

  defp draw_psychic_draw_cards(
         %Game{} = game,
         player,
         %CardInstance{} = source_card,
         %Turn{} = turn
       ) do
    with {:ok, draw_count} <- AbilityEffects.psychic_draw_count(source_card),
         {:ok, drawn_cards} <- draw_cards_from_deck(game.id, player, draw_count),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_psychic_draw_used_marker(current_source_card, turn)
           }) do
      {:ok, %{draw_count: draw_count, drawn_cards: drawn_cards}}
    end
  end

  defp require_top_deck_choice(top_cards, chosen_card_instance_id) when is_list(top_cards) do
    case Enum.find(top_cards, &(&1.id == chosen_card_instance_id)) do
      %CardInstance{} = chosen_card -> {:ok, chosen_card}
      nil -> {:error, :recon_directive_choice_not_in_top_two}
    end
  end

  defp resolve_recon_directive_choice(
         %Game{} = game,
         player,
         %CardInstance{} = source_card,
         %CardInstance{} = chosen_card,
         other_cards,
         %Turn{} = turn
       )
       when is_list(other_cards) do
    with {:ok, moved_chosen_card} <-
           move_deck_card_to_hand(game.id, player.player_id, chosen_card),
         {:ok, bottomed_cards} <-
           reorder_deck_cards_to_bottom(game.id, player.player_id, other_cards),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, _source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_recon_directive_used_marker(current_source_card, turn)
           }) do
      {:ok, %{chosen_card: moved_chosen_card, bottomed_cards: bottomed_cards}}
    end
  end

  defp reorder_deck_cards_to_bottom(_game_id, _player_id, []), do: {:ok, []}

  defp reorder_deck_cards_to_bottom(game_id, player_id, bottom_cards) do
    bottom_card_ids = MapSet.new(bottom_cards, & &1.id)

    with {:ok, deck_cards} <- cards_in_zone(game_id, player_id, :deck) do
      bottom_cards_in_deck = Enum.filter(deck_cards, &MapSet.member?(bottom_card_ids, &1.id))
      top_cards = Enum.reject(deck_cards, &MapSet.member?(bottom_card_ids, &1.id))

      with {:ok, _reordered_cards} <- reorder_deck_cards(top_cards ++ bottom_cards_in_deck) do
        {:ok, bottom_cards_in_deck}
      end
    end
  end

  defp draw_and_shuffle_run_away_draw(
         %Game{} = game,
         player,
         %CardInstance{} = source_card,
         %Turn{} = turn
       ) do
    with {:ok, draw_count} <- AbilityEffects.run_away_draw_count(source_card),
         {:ok, drawn_cards} <- draw_cards_from_deck(game.id, player, draw_count),
         {:ok, current_source_card} <- get_card(game.id, source_card.id),
         {:ok, marked_source_card} <-
           update(current_source_card, :set_markers, %{
             markers: AbilityEffects.put_run_away_draw_used_marker(current_source_card, turn)
           }),
         {:ok, shuffled_stack_cards} <-
           shuffle_in_play_stack_into_deck(game, turn, player, marked_source_card) do
      {:ok,
       %{
         draw_count: draw_count,
         drawn_cards: drawn_cards,
         shuffled_stack_cards: shuffled_stack_cards
       }}
    end
  end

  defp shuffle_in_play_stack_into_deck(
         %Game{} = game,
         %Turn{} = turn,
         player,
         %CardInstance{} = source_card
       ) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game.id, source_card.id),
         stack_cards = [source_card | attached_cards],
         {:ok, returned_cards} <- return_stack_to_deck(game.id, player.player_id, stack_cards),
         {:ok, _shuffled_deck} <-
           shuffle_player_deck_for_ability(
             game,
             turn,
             player.player_id,
             source_card,
             AbilityEffects.run_away_draw_ability_id()
           ) do
      {:ok, returned_cards}
    end
  end

  defp return_stack_to_deck(game_id, player_id, stack_cards) do
    with {:ok, deck_count} <- CardStore.deck_count(game_id, player_id) do
      stack_cards
      |> Enum.with_index(deck_count + 1)
      |> Enum.map(fn {card, position} ->
        update(card, :shuffle_into_deck, %{
          attached_to_card_instance_id: nil,
          evolves_from_card_instance_id: nil,
          damage: 0,
          status: nil,
          position: position
        })
      end)
      |> collect_results()
    end
  end

  defp shuffle_player_deck_for_ability(
         %Game{} = game,
         %Turn{} = turn,
         player_id,
         %CardInstance{} = source_card,
         ability_id
       ) do
    context =
      {:ability_deck_shuffle, player_id, turn.turn_number, source_card.instance_id, ability_id}

    with {:ok, cards} <- cards_in_zone(game.id, player_id, :deck) do
      cards
      |> shuffle_cards(game.rng_seed, context)
      |> reorder_deck_cards()
    end
  end

  defp shuffle_cards(cards, seed, context) when is_binary(seed),
    do: Rng.shuffle(cards, seed, context)

  defp shuffle_cards(cards, _seed, _context), do: Enum.shuffle(cards)

  defp reorder_deck_cards(cards) do
    cards
    |> Enum.with_index(1)
    |> Enum.map(fn {card, position} -> update(card, :reorder_deck, %{position: position}) end)
    |> collect_results()
  end

  defp draw_cards_from_deck(game_id, player, draw_count) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, draw_count) do
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

  defp teal_dance_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         %CardInstance{} = energy_card,
         ability_result
       ) do
    drawn_cards = ability_result.drawn_cards

    maybe_put(
      %{
        turn_id: turn.id,
        source: EventPayloads.card_source(source_card),
        source_card_id: source_card.card_id,
        source_card_instance_id: source_card.id,
        ability_id: Atom.to_string(AbilityEffects.teal_dance_ability_id()),
        effect_type: :attach_basic_grass_energy_from_hand_to_self_then_draw,
        energy_card_instance_id: energy_card.id,
        attached_position: ability_result.attached_position,
        drawn_card_count: length(drawn_cards),
        cards:
          teal_dance_moved_card_payloads(source_card, ability_result.attached_energy, drawn_cards),
        public_note: teal_dance_public_note(length(drawn_cards))
      },
      :recovered_special_condition,
      ability_result.recovered_special_condition
    )
  end

  defp teal_dance_moved_card_payloads(source_card, attached_energy, drawn_cards) do
    [
      attached_energy
      |> List.wrap()
      |> EventPayloads.moved_cards(:hand, :attached)
      |> List.first()
      |> Map.put(
        :to_attached_to_card_instance_id,
        source_card.id
      )
    ] ++ EventPayloads.moved_cards(drawn_cards, :deck, :hand)
  end

  defp teal_dance_public_note(1), do: "Teal Dance attached Grass Energy and drew 1 card."

  defp teal_dance_public_note(card_count) do
    "Teal Dance attached Grass Energy and drew #{card_count} cards."
  end

  defp seething_spirit_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         ability_result
       ) do
    maybe_put(
      %{
        turn_id: turn.id,
        source: EventPayloads.card_source(source_card),
        source_card_id: source_card.card_id,
        source_card_instance_id: source_card.id,
        ability_id: Atom.to_string(AbilityEffects.seething_spirit_ability_id()),
        effect_type: :attach_basic_energy_from_discard_to_own_pokemon,
        energy_card_instance_id: energy_card.id,
        target_card_instance_id: target_card.id,
        attached_position: ability_result.attached_position,
        cards: seething_spirit_moved_card_payloads(target_card, ability_result.attached_energy),
        public_note: "Seething Spirit attached Basic Energy from the discard pile."
      },
      :recovered_special_condition,
      ability_result.recovered_special_condition
    )
  end

  defp seething_spirit_moved_card_payloads(target_card, attached_energy) do
    attached_energy
    |> List.wrap()
    |> EventPayloads.moved_cards(:discard, :attached)
    |> Enum.map(&Map.put(&1, :to_attached_to_card_instance_id, target_card.id))
  end

  defp flip_the_script_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         ability_result
       ) do
    drawn_cards = ability_result.drawn_cards

    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.flip_the_script_ability_id()),
      effect_type: :draw_if_own_pokemon_knocked_out_last_turn,
      drawn_card_count: length(drawn_cards),
      cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand),
      public_note: flip_the_script_public_note(length(drawn_cards))
    }
  end

  defp flip_the_script_public_note(1), do: "Flip the Script drew 1 card."

  defp flip_the_script_public_note(card_count) do
    "Flip the Script drew #{card_count} cards."
  end

  defp psychic_draw_event_payload(%Turn{} = turn, %CardInstance{} = source_card, ability_result) do
    drawn_cards = ability_result.drawn_cards

    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.psychic_draw_ability_id()),
      effect_type: :evolution_draw,
      drawn_card_count: length(drawn_cards),
      cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand),
      public_note: psychic_draw_public_note(source_card, length(drawn_cards))
    }
  end

  defp psychic_draw_public_note(%CardInstance{card_id: "MEG-056"}, 1) do
    "Psychic Draw drew 1 card."
  end

  defp psychic_draw_public_note(%CardInstance{card_id: "MEG-056"}, card_count) do
    "Psychic Draw drew #{card_count} cards."
  end

  defp psychic_draw_public_note(%CardInstance{}, 1), do: "Psychic Draw drew 1 card."

  defp psychic_draw_public_note(%CardInstance{}, card_count) do
    "Psychic Draw drew #{card_count} cards."
  end

  defp recon_directive_event_payload(
         %Turn{} = turn,
         %CardInstance{} = source_card,
         ability_result
       ) do
    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.recon_directive_ability_id()),
      effect_type: :top_two_choose_one_to_hand_other_to_bottom,
      chosen_card_instance_id: ability_result.chosen_card.id,
      bottomed_card_instance_ids: Enum.map(ability_result.bottomed_cards, & &1.id),
      cards: EventPayloads.moved_cards([ability_result.chosen_card], :deck, :hand),
      public_note:
        "Recon Directive put 1 of the top cards into hand and the other on the bottom of the deck."
    }
  end

  defp run_away_draw_event_payload(%Turn{} = turn, %CardInstance{} = source_card, ability_result) do
    %{
      turn_id: turn.id,
      source: EventPayloads.card_source(source_card),
      source_card_id: source_card.card_id,
      source_card_instance_id: source_card.id,
      ability_id: Atom.to_string(AbilityEffects.run_away_draw_ability_id()),
      effect_type: :draw_then_shuffle_self_into_deck,
      drawn_card_count: length(ability_result.drawn_cards),
      shuffled_card_instance_ids: Enum.map(ability_result.shuffled_stack_cards, & &1.id),
      cards:
        EventPayloads.moved_cards(ability_result.drawn_cards, :deck, :hand) ++
          EventPayloads.moved_cards(ability_result.shuffled_stack_cards, :in_play, :deck),
      public_note: run_away_draw_public_note(length(ability_result.drawn_cards))
    }
  end

  defp run_away_draw_public_note(1) do
    "Run Away Draw drew 1 card, then shuffled Dudunsparce and attached cards into the deck."
  end

  defp run_away_draw_public_note(card_count) do
    "Run Away Draw drew #{card_count} cards, then shuffled Dudunsparce and attached cards into the deck."
  end

  defp subjugating_chains_public_note(%{status_applied?: true}) do
    "Pecharunt ex used Subjugating Chains and switched a Benched Darkness Pokémon into the Active Spot. The new Active Pokémon is now Poisoned."
  end

  defp subjugating_chains_public_note(_poison_result) do
    "Pecharunt ex used Subjugating Chains and switched a Benched Darkness Pokémon into the Active Spot."
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
