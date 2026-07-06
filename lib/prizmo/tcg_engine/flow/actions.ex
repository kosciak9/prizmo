defmodule Prizmo.TcgEngine.Flow.Actions do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState,
    only: [
      require_all_players_have_active: 1,
      require_all_players_have_prizes: 2,
      require_no_active: 2,
      require_no_prizes_placed: 1
    ]

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [require_basic_pokemon: 1]

  import Prizmo.TcgEngine.CardStore,
    only: [get_card: 2, next_bench_position: 2]

  import Prizmo.TcgEngine.EventLog, only: [write_event: 4, write_snapshot: 3]
  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [
      require_active_player: 2,
      require_card_owned_by_player: 2,
      require_card_zone: 2,
      require_turn_player: 2
    ]

  import Prizmo.TcgEngine.TurnDraw, only: [draw_one_for_turn: 2]

  import Prizmo.TcgEngine.TurnFlow,
    only: [next_turn_number: 1, next_turn_player_id: 1, opponent_player_id: 2]

  import Prizmo.TcgEngine.TurnStore, only: [current_turn: 1]

  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardPlay
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Flow.Context
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.GameSetup
  alias Prizmo.TcgEngine.Mechanics
  alias Prizmo.TcgEngine.Rng
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.SetupStore
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.Turn

  @coin_faces [:heads, :tails]

  def opening_hands_not_dealt?(%Context{game: %Game{} = game}, _attrs) do
    GameSetup.require_no_setup_cards_moved(game.id) == :ok
  end

  def all_players_have_active?(%Context{game: %Game{} = game}, _attrs) do
    require_all_players_have_active(game.id) == :ok
  end

  def all_players_setup_ready?(%Context{game: %Game{} = game, players: players}, _attrs) do
    require_all_players_have_active(game.id) == :ok and Enum.all?(players, & &1.setup_ready?)
  end

  def setup_prizes_complete?(%Context{game: %Game{} = game}, _attrs) do
    require_all_players_have_active(game.id) == :ok and
      require_all_players_have_prizes(game.id, 6) == :ok
  end

  def can_start_turn?(%Context{game: %Game{} = game}, _attrs) do
    match?({:ok, _player_id}, next_turn_player_id(game))
  end

  def can_draw_for_turn?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :start}} -> true
      _other -> false
    end
  end

  def can_open_action_window?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :drawn}} -> true
      _other -> false
    end
  end

  def can_end_turn?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :action_window}} ->
        CardPlay.require_no_awaiting_pending_effect(game.id) == :ok

      _other ->
        false
    end
  end

  def can_create_end_turn_tool_effect_prompt?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :action_window, active_player_id: active_player_id} = turn} ->
        CardPlay.require_no_awaiting_pending_effect(game.id) == :ok and
          ToolEffects.end_turn_prompt_available?(game.id, active_player_id, turn)

      _other ->
        false
    end
  end

  def can_create_attack_end_turn_tool_effect_prompt?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :attack_resolving, active_player_id: active_player_id} = turn} ->
        CardPlay.require_no_awaiting_pending_effect(game.id) == :ok and
          require_all_players_have_active(game.id) == :ok and
          game.active_player_id == active_player_id and
          ToolEffects.end_turn_prompt_available?(game.id, active_player_id, turn)

      _other ->
        false
    end
  end

  def can_resolve_declared_attack?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok,
       %Turn{
         status: :attack_declared,
         active_player_id: active_player_id,
         pending_attack_id: attack_id,
         pending_attacker_card_instance_id: attacker_card_instance_id,
         pending_defender_card_instance_id: defender_card_instance_id
       }} ->
        with {:ok, attacker_card} <- get_card(game.id, attacker_card_instance_id),
             {:ok, defender_card} <- get_card(game.id, defender_card_instance_id),
             {:ok, attack} <- CardCatalog.fetch_attack(attacker_card.card_id, attack_id) do
          AttackEffects.auto_resolvable_without_input?(
            game.id,
            active_player_id,
            defender_card,
            attack
          )
        else
          _error -> true
        end

      _other ->
        false
    end
  end

  def can_finish_attack?(%Context{game: %Game{} = game}, _attrs) do
    case current_turn(game.id) do
      {:ok, %Turn{status: :attack_resolving, active_player_id: active_player_id}} ->
        CardPlay.require_no_awaiting_pending_effect(game.id) == :ok and
          require_all_players_have_active(game.id) == :ok and
          game.active_player_id == active_player_id

      _other ->
        false
    end
  end

  def record_coin_toss(%Context{} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    call = normalize_coin_face(Map.fetch!(attrs, :call))

    with {:ok, call} <- call,
         :ok <- require_player(context, player_id),
         :ok <- require_no_coin_toss(context.game),
         {:ok, result} <- random_coin_face(context.game, player_id, call),
         winner_player_id = coin_toss_winner(context, player_id, call, result),
         {:ok, game} <-
           update(context.game, :record_coin_toss, %{
             flow_state: :pregame_awaiting_starting_player_choice,
             coin_toss_calling_player_id: player_id,
             coin_toss_call: call,
             coin_toss_result: result,
             coin_toss_winner_player_id: winner_player_id
           }),
         {:ok, event} <-
           write_event(
             game,
             :coin_toss_resolved,
             player_id,
             coin_toss_payload(game, player_id, call, result, winner_player_id)
           ),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def choose_starting_player(%Context{} = context, attrs) do
    chooser_player_id = Map.fetch!(attrs, :chooser_player_id)
    starting_player_id = Map.fetch!(attrs, :starting_player_id)

    with :ok <- require_player(context, chooser_player_id),
         :ok <- require_player(context, starting_player_id),
         :ok <- require_coin_toss_winner(context.game, chooser_player_id),
         {:ok, game} <-
           update(context.game, :choose_starting_player, %{
             flow_state: :setup_dealing_opening_hands,
             active_player_id: starting_player_id,
             first_player_id: starting_player_id,
             starting_player_chosen_by_player_id: chooser_player_id
           }),
         {:ok, _setup} <- create(Setup, :create, %{game_id: game.id}),
         {:ok, event} <-
           write_event(game, :starting_player_chosen, chooser_player_id, %{
             starting_player_id: starting_player_id
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def deal_opening_hands(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, setup} <- SetupStore.get_setup(game.id),
         {:ok, setup} <- update(setup, :draw_opening_hand, %{}),
         :ok <- GameSetup.require_no_setup_cards_moved(game.id),
         {:ok, player_hand_facts} <- GameSetup.draw_opening_cards(game.id),
         :ok <- require_no_prizes_placed(game.id),
         {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_active}),
         {:ok, event} <-
           write_event(
             game,
             :opening_hands_drawn,
             nil,
             setup_move_payload(setup, player_hand_facts)
           ),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def choose_setup_active(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    card_instance_id = Map.fetch!(attrs, :card_instance_id)

    with :ok <- require_player(context, player_id),
         :ok <- require_setup_player_not_ready(context, player_id),
         {:ok, card} <- get_card(game.id, card_instance_id),
         :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         :ok <- require_basic_pokemon(card.card_id),
         :ok <- require_no_active(game.id, player_id),
         {:ok, _card} <- update(card, :choose_active, %{position: 1, turn_entered_play: 0}),
         {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_active}),
         {:ok, event} <-
           write_event(game, :setup_active_chosen, player_id, %{card_instance_id: card.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def mulligan_opening_hand(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)

    with :ok <- require_player(context, player_id),
         :ok <- require_setup_player_not_ready(context, player_id),
         :ok <- require_no_active(game.id, player_id),
         {:ok, setup} <- SetupStore.require_setup_status(game.id, :hands_drawn),
         {:ok, false} <- GameSetup.opening_hand_has_basic?(game.id, player_id),
         %GamePlayer{} = player <- player(context, player_id),
         {:ok, mulligan_fact} <- GameSetup.mulligan_opening_hand(game, player),
         {:ok, event} <-
           write_event(
             game,
             :opening_hand_mulligan,
             player_id,
             setup_mulligan_payload(setup, mulligan_fact)
           ),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    else
      {:ok, true} -> {:error, :opening_hand_has_basic}
      nil -> {:error, :player_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def open_setup_bench_choices(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_bench}),
         {:ok, event} <- write_event(game, :setup_bench_choices_opened, nil, %{}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def choose_setup_bench(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    card_instance_id = Map.fetch!(attrs, :card_instance_id)

    with :ok <- require_player(context, player_id),
         :ok <- require_setup_player_not_ready(context, player_id),
         :ok <- require_player_has_active(game.id, player_id),
         {:ok, card} <- get_card(game.id, card_instance_id),
         :ok <- require_card_owned_by_player(card, player_id),
         :ok <- require_card_zone(card, :hand),
         :ok <- require_basic_pokemon(card.card_id),
         {:ok, position} <- next_bench_position(game.id, player_id),
         {:ok, _card} <-
           update(card, :play_to_bench, %{position: position, turn_entered_play: 0}),
         {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_bench}),
         {:ok, event} <-
           write_event(game, :setup_bench_chosen, player_id, %{
             card_instance_id: card.id,
             position: position
           }),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def draw_mulligan_bonus(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    count = Map.fetch!(attrs, :count)

    with :ok <- require_player(context, player_id),
         :ok <- require_setup_player_not_ready(context, player_id),
         :ok <- require_player_has_active(game.id, player_id),
         {:ok, setup} <- SetupStore.require_setup_status(game.id, :hands_drawn),
         :ok <- require_no_prizes_placed(game.id),
         %GamePlayer{} = player <- player(context, player_id),
         {:ok, bonus_fact} <- GameSetup.draw_mulligan_bonus_cards(game, player, count),
         {:ok, event} <-
           write_event(
             game,
             :mulligan_bonus_drawn,
             player_id,
             setup_mulligan_payload(setup, bonus_fact)
           ),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    else
      nil -> {:error, :player_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def finish_setup_choices(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)

    with :ok <- require_player(context, player_id),
         :ok <- require_setup_player_not_ready(context, player_id),
         :ok <- require_player_has_active(game.id, player_id),
         %GamePlayer{} = player <- player(context, player_id),
         {:ok, _player} <- update(player, :mark_setup_ready, %{}),
         {:ok, game} <-
           update(game, :set_flow_state, %{flow_state: :setup_choosing_opening_bench}),
         {:ok, event} <- write_event(game, :setup_player_ready, player_id, %{}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def place_setup_prizes(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, setup} <- SetupStore.get_setup(game.id),
         :ok <- require_all_players_have_active(game.id),
         :ok <- require_no_prizes_placed(game.id),
         {:ok, setup} <- update(setup, :place_prizes, %{}),
         {:ok, player_prize_facts} <- GameSetup.place_prize_cards(game.id),
         {:ok, game} <- update(game, :set_flow_state, %{flow_state: :setup_completing_setup}),
         {:ok, event} <-
           write_event(game, :prizes_placed, nil, setup_move_payload(setup, player_prize_facts)),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def complete_setup(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, setup} <- SetupStore.get_setup(game.id),
         :ok <- require_all_players_have_active(game.id),
         :ok <- require_all_players_have_prizes(game.id, 6),
         {:ok, setup} <- update(setup, :complete_setup, %{}),
         {:ok, game} <- update(game, :complete_setup, %{}),
         {:ok, game} <- update(game, :set_flow_state, %{flow_state: :turn_starting_turn}),
         {:ok, event} <- write_event(game, :setup_completed, nil, %{setup_id: setup.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def start_turn(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, next_player_id} <- next_turn_player_id(game),
         {:ok, turn_number} <- next_turn_number(game.id),
         {:ok, next_player} <- get_context_player(game.id, next_player_id),
         {:ok, _player} <- update(next_player, :reset_turn_flags, %{}),
         {:ok, game} <- update(game, :set_active_player, %{active_player_id: next_player_id}),
         {:ok, turn} <-
           create(Turn, :create, %{
             game_id: game.id,
             turn_number: turn_number,
             active_player_id: next_player_id
           }),
         {:ok, game} <- update(game, :set_flow_state, %{flow_state: :turn_drawing_for_turn}),
         {:ok, event} <- write_event(game, :turn_started, next_player_id, %{turn_id: turn.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def draw_for_turn(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id),
         {:ok, turn} <- update(turn, :draw_for_turn, %{}) do
      case draw_one_for_turn(game.id, turn.active_player_id) do
        {:ok, drawn_card} ->
          with {:ok, game} <-
                 update(game, :set_flow_state, %{flow_state: :turn_opening_action_window}),
               {:ok, event} <-
                 write_event(game, :turn_card_drawn, turn.active_player_id, %{
                   turn_id: turn.id,
                   card: [drawn_card] |> EventPayloads.moved_cards(:deck, :hand) |> List.first()
                 }),
               {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
            {:ok, game}
          end

        {:error, :cannot_draw_from_empty_deck} ->
          with {:ok, winner_player_id} <- opponent_player_id(game.id, turn.active_player_id),
               {:ok, game} <- update(game, :finish, %{winner_player_id: winner_player_id}),
               {:ok, game} <- update(game, :set_flow_state, %{flow_state: :finished}),
               {:ok, event} <-
                 write_event(game, :deck_out, turn.active_player_id, %{
                   turn_id: turn.id,
                   winner_player_id: winner_player_id
                 }),
               {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
            {:ok, game}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def open_action_window(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id),
         {:ok, turn} <- update(turn, :open_action_window, %{}),
         {:ok, game} <- update(game, :set_flow_state, %{flow_state: :turn_action_window}),
         {:ok, event} <-
           write_event(game, :action_window_opened, turn.active_player_id, %{turn_id: turn.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def pass_turn(%Context{game: %Game{} = game} = context, attrs) do
    player_id = Map.fetch!(attrs, :player_id)

    with :ok <- require_player(context, player_id),
         :ok <- require_active_player(game, player_id),
         {:ok, turn} <- current_turn(game.id),
         :ok <- require_turn_player(turn, player_id),
         :ok <- require_turn_status(turn, :action_window),
         {:ok, game} <- update(game, :set_flow_state, %{flow_state: :turn_ending_turn}),
         {:ok, event} <- write_event(game, :turn_passed, player_id, %{turn_id: turn.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index) do
      {:ok, game}
    end
  end

  def end_turn(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id),
         :ok <- require_turn_status(turn, :action_window),
         {:ok, turn} <- update(turn, :pass, %{}),
         {:ok, event} <-
           write_event(game, :turn_ended, turn.active_player_id, %{turn_id: turn.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
         {:ok, game} <- Mechanics.process_pokemon_checkup(game) do
      update(game, :set_flow_state, %{flow_state: :turn_starting_turn})
    end
  end

  def create_end_turn_tool_effect_prompt(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id) do
      ToolEffects.create_end_turn_prompt(game, turn)
    end
  end

  def declare_attack(%Context{game: %Game{} = game}, attrs) do
    player_id = Map.fetch!(attrs, :player_id)
    attack_id = Map.fetch!(attrs, :attack_id)

    with {:ok, game} <- Mechanics.declare_attack_legacy(game, player_id, attack_id) do
      update(game, :set_flow_state, %{flow_state: :turn_attack_declared})
    end
  end

  def resolve_declared_attack(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id),
         {:ok, game} <- Mechanics.resolve_declared_attack(game, turn.active_player_id, %{}) do
      update(game, :set_flow_state, %{flow_state: :turn_attack_resolving})
    end
  end

  def finish_attack(%Context{game: %Game{} = game}, _attrs) do
    with {:ok, turn} <- current_turn(game.id),
         {:ok, game} <- Mechanics.finish_attack(game, turn.active_player_id),
         {:ok, event} <-
           write_event(game, :turn_ended, turn.active_player_id, %{turn_id: turn.id}),
         {:ok, _snapshot} <- write_snapshot(game.id, event.id, event.index),
         {:ok, game} <- Mechanics.process_pokemon_checkup(game) do
      update(game, :set_flow_state, %{flow_state: :turn_starting_turn})
    end
  end

  defp normalize_coin_face(face) when face in @coin_faces, do: {:ok, face}
  defp normalize_coin_face("heads"), do: {:ok, :heads}
  defp normalize_coin_face("tails"), do: {:ok, :tails}
  defp normalize_coin_face(face), do: {:error, {:invalid_coin_call, face}}

  defp random_coin_face(%Game{rng_seed: seed}, player_id, call) when is_binary(seed) do
    Rng.choice(@coin_faces, seed, coin_toss_rng_context(player_id, call))
  end

  defp random_coin_face(%Game{}, _player_id, _call) do
    {:ok, Enum.random(@coin_faces)}
  end

  defp coin_toss_payload(%Game{} = game, player_id, call, result, winner_player_id) do
    payload = %{
      call: Atom.to_string(call),
      result: Atom.to_string(result),
      winner_player_id: winner_player_id
    }

    case game.rng_seed do
      seed when is_binary(seed) ->
        Map.merge(payload, %{
          rng_algorithm: game.rng_algorithm || Rng.algorithm(),
          rng_context: coin_toss_rng_context_label(player_id, call),
          rng_seed_source: game.rng_seed_source
        })

      _seed ->
        payload
    end
  end

  defp setup_move_payload(%Setup{} = setup, player_facts) do
    %{
      setup_id: setup.id,
      players: player_facts
    }
  end

  defp setup_mulligan_payload(%Setup{} = setup, mulligan_fact) do
    Map.put(mulligan_fact, :setup_id, setup.id)
  end

  defp coin_toss_rng_context(player_id, call), do: {:coin_toss, player_id, call}

  defp coin_toss_rng_context_label(player_id, call), do: "coin_toss:#{player_id}:#{call}"

  defp coin_toss_winner(%Context{} = context, calling_player_id, call, result) do
    if call == result do
      calling_player_id
    else
      context.players
      |> Enum.reject(&(&1.player_id == calling_player_id))
      |> List.first()
      |> Map.fetch!(:player_id)
    end
  end

  defp require_player(%Context{} = context, player_id) do
    if Context.player?(context, player_id), do: :ok, else: {:error, :player_not_found}
  end

  defp require_setup_player_not_ready(%Context{} = context, player_id) do
    case player(context, player_id) do
      %GamePlayer{setup_ready?: false} -> :ok
      %GamePlayer{setup_ready?: true} -> {:error, :setup_player_already_ready}
      nil -> {:error, :player_not_found}
    end
  end

  defp require_player_has_active(game_id, player_id) do
    case require_no_active(game_id, player_id) do
      {:error, :active_already_chosen} -> :ok
      :ok -> {:error, :setup_active_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_turn_status(%Turn{status: status}, status), do: :ok

  defp require_turn_status(%Turn{status: actual}, expected),
    do: {:error, {:invalid_turn_status, actual, expected}}

  defp player(%Context{players: players}, player_id) do
    Enum.find(players, &(&1.player_id == player_id))
  end

  defp get_context_player(game_id, player_id) do
    case Prizmo.TcgEngine.PlayerStore.get_player(game_id, player_id) do
      {:ok, %GamePlayer{} = player} -> {:ok, player}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_no_coin_toss(%Game{coin_toss_result: nil}), do: :ok
  defp require_no_coin_toss(%Game{}), do: {:error, :coin_toss_already_resolved}

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: player_id}, player_id), do: :ok

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: nil}, _player_id),
    do: {:error, :coin_toss_not_resolved}

  defp require_coin_toss_winner(%Game{coin_toss_winner_player_id: winner_player_id}, _player_id),
    do: {:error, {:not_coin_toss_winner, winner_player_id}}
end
