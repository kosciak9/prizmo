defmodule Prizmo.Tcg.Sim.Engine do
  @moduledoc """
  First reducer for the ExUnit-first Pokémon TCG simulator.

  This slice is deliberately state-machine-first. Card behavior will be added on
  top of these transitions after lifecycle semantics are stable.
  """

  alias Prizmo.Tcg.Cards.Metadata
  alias Prizmo.Tcg.Sim.Action
  alias Prizmo.Tcg.Sim.CardInstance
  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.Tcg.Sim.GameState
  alias Prizmo.Tcg.Sim.History
  alias Prizmo.Tcg.Sim.Hooks
  alias Prizmo.Tcg.Sim.PlayerState
  alias Prizmo.Tcg.Sim.StateMachines.CardLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.GameLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.TurnLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.ZoneMovement

  @secret_box_trainer_types [:item, :tool, :supporter, :stadium]

  @type result :: {:ok, GameState.t()} | {:error, term()}

  def new_game(opts) do
    players = Keyword.fetch!(opts, :players)
    active_player = Keyword.fetch!(opts, :active_player)

    state_players =
      Map.new(players, fn {player_id, deck_ids} ->
        {player_id,
         %PlayerState{
           id: player_id,
           deck: instantiate_deck(player_id, deck_ids),
           expected_card_count: length(deck_ids)
         }}
      end)

    %GameState{players: state_players, active_player: active_player, first_player: active_player}
  end

  def apply_action(%GameState{} = state, %Action{} = action) do
    with {:ok, next_state} <- reduce(state, action) do
      {:ok, History.record(state, action, next_state)}
    end
  end

  def undo(%GameState{} = state), do: History.undo(state)
  def redo(%GameState{} = state), do: History.redo(state)

  defp reduce(state, %Action{type: :start_setup}) do
    with {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :start_setup) do
      {:ok, %{state | game_lifecycle: game_lifecycle, log: ["setup started" | state.log]}}
    end
  end

  defp reduce(state, %Action{type: :draw_opening_hand}) do
    with :ok <- require_game_lifecycle(state, :setup) do
      Enum.reduce_while(Map.keys(state.players), {:ok, state}, fn player_id, {:ok, state} ->
        case draw_cards(state, player_id, 7) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp reduce(state, %Action{type: :take_mulligan, player_id: player_id}) do
    with :ok <- require_game_lifecycle(state, :setup),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_no_setup_pokemon_chosen(player),
         :ok <- require_opening_hand_ready_for_mulligan(player),
         :ok <- require_no_basic_pokemon_in_hand(player),
         {:ok, state} <- shuffle_hand_into_deck(state, player_id),
         {:ok, state} <- draw_cards(state, player_id, 7),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{player | mulligans_taken: player.mulligans_taken + 1}
      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :draw_mulligan_bonus,
         player_id: player_id,
         params: %{count: count}
       })
       when is_integer(count) and count >= 0 do
    with :ok <- require_game_lifecycle(state, :setup),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, opponent} <- fetch_player(state, opponent_id),
         :ok <- require_mulligan_bonus_available(player, opponent, count),
         {:ok, state} <- draw_cards(state, player_id, count),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{
        player
        | mulligan_bonus_draws_taken: player.mulligan_bonus_draws_taken + count
      }

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :choose_active_from_hand,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_game_lifecycle(state, :setup),
         {:ok, player} <- fetch_player(state, player_id),
         true <- is_nil(player.active) || {:error, {:active_already_chosen, player_id}},
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_basic_pokemon(metadata),
         {:ok, :active} <- ZoneMovement.transition(:hand, :active),
         {:ok, :in_play_basic} <- CardLifecycle.transition(card.lifecycle, :play_basic) do
      choose_active(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :choose_setup_bench_from_hand,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_game_lifecycle(state, :setup),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_basic_pokemon(metadata),
         {:ok, :bench} <- ZoneMovement.transition(:hand, :bench),
         {:ok, :in_play_basic} <- CardLifecycle.transition(card.lifecycle, :play_basic) do
      move_hand_card_to_bench(state, player_id, card)
    end
  end

  defp reduce(state, %Action{type: :place_prizes}) do
    with :ok <- require_game_lifecycle(state, :setup),
         :ok <- require_all_players_have_active(state),
         :ok <- require_no_player_has_prizes(state) do
      Enum.reduce_while(Map.keys(state.players), {:ok, state}, fn player_id, {:ok, state} ->
        case place_prizes(state, player_id, 6) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp reduce(state, %Action{type: :complete_setup}) do
    with {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :complete_setup),
         :ok <- require_all_players_have_active(state),
         :ok <- require_all_players_have_prizes(state, 6),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :start_turn) do
      {:ok,
       %{
         state
         | game_lifecycle: game_lifecycle,
           turn_lifecycle: turn_lifecycle,
           turn_number: state.turn_number + 1,
           log: ["setup completed" | state.log]
       }}
    end
  end

  defp reduce(state, %Action{type: :draw_for_turn, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :draw_for_turn) do
      case draw_card(state, player_id) do
        {:ok, state} ->
          {:ok,
           %{
             state
             | turn_lifecycle: turn_lifecycle,
               log: ["#{player_id} drew for turn" | state.log]
           }}

        {:error, :cannot_draw_from_empty_deck} ->
          with {:ok, winner} <- opponent_id(state, player_id) do
            {:ok,
             %{
               state
               | winner: winner,
                 game_lifecycle: :finished,
                 turn_lifecycle: turn_lifecycle,
                 log: ["#{player_id} lost by deck-out" | state.log]
             }}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp reduce(state, %Action{type: :skip_draw_for_turn, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         {:ok, turn_lifecycle} <-
           TurnLifecycle.transition(state.turn_lifecycle, :skip_draw_for_turn) do
      {:ok,
       %{
         state
         | turn_lifecycle: turn_lifecycle,
           log: ["#{player_id} skipped draw for turn" | state.log]
       }}
    end
  end

  defp reduce(state, %Action{type: :open_action_window}) do
    with {:ok, turn_lifecycle} <-
           TurnLifecycle.transition(state.turn_lifecycle, :open_action_window) do
      {:ok, %{state | turn_lifecycle: turn_lifecycle}}
    end
  end

  defp reduce(state, %Action{
         type: :play_basic_to_bench,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_basic_pokemon(metadata),
         {:ok, :bench} <- ZoneMovement.transition(:hand, :bench),
         {:ok, :in_play_basic} <- CardLifecycle.transition(card.lifecycle, :play_basic) do
      move_hand_card_to_bench(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :attach_energy,
         player_id: player_id,
         params: %{instance_id: instance_id, target_id: target_id} = params
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_energy_attachment_available(player),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_energy(metadata),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <-
           require_attachment_effect_params(metadata, params, state, player_id, target_metadata),
         {:ok, :attached} <- ZoneMovement.transition(:hand, :attached),
         {:ok, :attached} <- CardLifecycle.transition(card.lifecycle, :attach) do
      attach_to_pokemon(state, player_id, card, target, params)
    end
  end

  defp reduce(state, %Action{
         type: :evolve_from_hand,
         player_id: player_id,
         params: %{instance_id: instance_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, evolution_card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, evolution_metadata} <- CardRegistry.fetch(evolution_card.card_id),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         :ok <- require_evolves_from(evolution_metadata, target),
         :ok <- require_first_turn_evolution_allowed(state),
         :ok <- require_can_evolve_this_turn(state, target, evolution_metadata),
         {:ok, :in_play_evolved} <- CardLifecycle.transition(evolution_card.lifecycle, :evolve) do
      evolve_pokemon(state, player_id, evolution_card, target)
    end
  end

  defp reduce(state, %Action{
         type: :retreat,
         player_id: player_id,
         params: %{bench_id: bench_id, attachment_ids: attachment_ids}
       })
       when is_list(attachment_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_active_pokemon(player_id, player),
         :ok <- require_can_retreat(player.active),
         :ok <- require_not_retreated_this_turn(player),
         {:ok, active_metadata} <- CardRegistry.fetch(player.active.card_id),
         {:ok, bench_card} <- find_in_player_zone(state, player_id, :bench, bench_id),
         {:ok, attachments} <- fetch_attachments(player.active, attachment_ids),
         :ok <- require_retreat_cost(player.active, active_metadata, attachments),
         {:ok, state} <- discard_attached_cards(state, player_id, player.active, attachments) do
      switch_own_bench_to_active(state, player_id, bench_card, retreated?: true)
    end
  end

  defp reduce(state, %Action{
         type: :switch_active_with_bench,
         player_id: player_id,
         params: %{bench_id: bench_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_active_pokemon(player_id, player),
         {:ok, bench_card} <- find_in_player_zone(state, player_id, :bench, bench_id) do
      switch_own_bench_to_active(state, player_id, bench_card, retreated?: false)
    end
  end

  defp reduce(state, %Action{
         type: :play_trainer_to_discard,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_trainer(metadata),
         :ok <- require_item_cards_playable_if_item(metadata, state, player_id),
         :ok <- require_ace_spec_cards_playable_if_ace_spec(metadata, state, player_id),
         :ok <- require_supporter_available_if_supporter(metadata, state, player_id),
         {:ok, :discard} <- ZoneMovement.transition(:hand, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(card.lifecycle, :discard) do
      discard_card_from_hand(state, player_id, card, metadata)
    end
  end

  defp reduce(state, %Action{
         type: :play_stadium,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_stadium(metadata),
         {:ok, :stadium} <- ZoneMovement.transition(:hand, :stadium),
         {:ok, :in_stadium} <- CardLifecycle.transition(card.lifecycle, :play_stadium) do
      play_stadium_card(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :attach_tool,
         player_id: player_id,
         params: %{instance_id: instance_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_tool(metadata),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         :ok <- require_no_tool_attached(target),
         {:ok, :attached} <- ZoneMovement.transition(:hand, :attached),
         {:ok, :attached} <- CardLifecycle.transition(card.lifecycle, :attach) do
      attach_tool_to_pokemon(state, player_id, card, target)
    end
  end

  defp reduce(state, %Action{
         type: :search_deck_to_hand,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :deck, instance_id),
         {:ok, :hand} <- ZoneMovement.transition(:deck, :hand),
         {:ok, :in_hand} <- CardLifecycle.transition(card.lifecycle, :search_to_hand) do
      move_deck_card_to_hand(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :put_basic_from_deck_to_bench,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :deck, instance_id),
         {:ok, metadata} <- CardRegistry.fetch(card.card_id),
         :ok <- require_basic_pokemon(metadata),
         {:ok, :bench} <- ZoneMovement.transition(:deck, :bench),
         {:ok, :in_play_basic} <- CardLifecycle.transition(card.lifecycle, :put_in_play) do
      move_deck_card_to_bench(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :discard_from_hand,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :hand, instance_id),
         {:ok, :discard} <- ZoneMovement.transition(:hand, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(card.lifecycle, :discard) do
      discard_card_from_hand(state, player_id, card, %{})
    end
  end

  defp reduce(state, %Action{
         type: :discard_from_deck,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :deck, instance_id),
         {:ok, :discard} <- ZoneMovement.transition(:deck, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(card.lifecycle, :discard_from_deck) do
      discard_card_from_deck(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :recover_discard_to_hand,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, card} <- find_in_player_zone(state, player_id, :discard, instance_id),
         {:ok, :hand} <- ZoneMovement.transition(:discard, :hand),
         {:ok, :in_hand} <- CardLifecycle.transition(card.lifecycle, :recover_to_hand) do
      move_discard_card_to_hand(state, player_id, card)
    end
  end

  defp reduce(state, %Action{
         type: :rare_candy,
         player_id: player_id,
         params: %{instance_id: candy_id, evolution_id: evolution_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, candy} <- find_in_player_zone(state, player_id, :hand, candy_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(candy, "MEG-125"),
         {:ok, evolution_card} <- find_in_player_zone(state, player_id, :hand, evolution_id),
         {:ok, evolution_metadata} <- CardRegistry.fetch(evolution_card.card_id),
         :ok <- require_stage_2(evolution_metadata),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         :ok <- require_rare_candy_evolves_from(evolution_metadata, target),
         :ok <- require_first_turn_evolution_allowed(state),
         :ok <- require_can_evolve_this_turn(state, target, evolution_metadata),
         {:ok, :discard} <- ZoneMovement.transition(:hand, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(candy.lifecycle, :discard),
         {:ok, :in_play_evolved} <- CardLifecycle.transition(evolution_card.lifecycle, :evolve),
         {:ok, state} <- discard_card_from_hand(state, player_id, candy, %{}) do
      evolve_pokemon(state, player_id, evolution_card, target)
    end
  end

  defp reduce(state, %Action{
         type: :buddy_buddy_poffin,
         player_id: player_id,
         params: %{instance_id: poffin_id, target_ids: target_ids}
       })
       when is_list(target_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         true <-
           length(target_ids) <= 2 || {:error, {:too_many_poffin_targets, length(target_ids)}},
         {:ok, poffin} <- find_in_player_zone(state, player_id, :hand, poffin_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(poffin, "TEF-144"),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <- require_poffin_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, poffin, %{}) do
      Enum.reduce_while(targets, {:ok, state}, fn target, {:ok, state} ->
        case move_deck_card_to_bench(state, player_id, target) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp reduce(state, %Action{
         type: :ultra_ball,
         player_id: player_id,
         params: %{instance_id: ultra_ball_id, discard_ids: discard_ids, target_id: target_id}
       })
       when is_list(discard_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         true <-
           length(discard_ids) == 2 ||
             {:error, {:wrong_ultra_ball_discard_count, length(discard_ids)}},
         {:ok, ultra_ball} <- find_in_player_zone(state, player_id, :hand, ultra_ball_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(ultra_ball, "MEG-131"),
         {:ok, discard_cards} <- fetch_hand_cards(state, player_id, discard_ids),
         {:ok, target} <- find_in_player_zone(state, player_id, :deck, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_pokemon(target_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, ultra_ball, %{}),
         {:ok, state} <- discard_hand_cards(state, player_id, discard_cards) do
      move_deck_card_to_hand(state, player_id, target)
    end
  end

  defp reduce(state, %Action{
         type: :boss_orders,
         player_id: player_id,
         params: %{instance_id: boss_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, boss} <- find_in_player_zone(state, player_id, :hand, boss_id),
         {:ok, boss_metadata} <- CardRegistry.fetch(boss.card_id),
         :ok <- require_card_id(boss, "MEG-114"),
         :ok <- require_supporter_available_if_supporter(boss_metadata, state, player_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, target} <- find_in_player_zone(state, opponent_id, :bench, target_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, boss, boss_metadata) do
      switch_opponent_bench_to_active(state, opponent_id, target)
    end
  end

  defp reduce(state, %Action{
         type: :discard_attached_energy_with_item,
         player_id: player_id,
         params:
           %{
             instance_id: item_id,
             target_player_id: target_player_id,
             target_id: target_id,
             attachment_id: attachment_id
           } =
             params
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, item} <- find_in_player_zone(state, player_id, :hand, item_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_hammer_item(item),
         :ok <- require_hammer_coin_result(item, params),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         {:ok, attachment} <- find_attachment(target, attachment_id),
         {:ok, attachment_metadata} <- CardRegistry.fetch(attachment.card_id),
         :ok <- require_energy(attachment_metadata),
         :ok <- require_hammer_can_discard(item, attachment_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, item, %{}) do
      if hammer_discards_energy?(item, params) do
        discard_attached_card(state, target_player_id, target, attachment)
      else
        {:ok, state}
      end
    end
  end

  defp reduce(state, %Action{
         type: :energy_switch,
         player_id: player_id,
         params: %{
           instance_id: energy_switch_id,
           source_id: source_id,
           target_id: target_id,
           attachment_id: attachment_id
         }
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         :ok <- require_different_in_play_targets(source_id, target_id),
         {:ok, energy_switch} <- find_in_player_zone(state, player_id, :hand, energy_switch_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(energy_switch, "MEG-115"),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, _target} <- find_in_play(state, player_id, target_id),
         {:ok, attachment} <- find_attachment(source, attachment_id),
         {:ok, attachment_metadata} <- CardRegistry.fetch(attachment.card_id),
         :ok <- require_basic_energy(attachment_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, energy_switch, %{}) do
      move_attached_card_between_own_pokemon(
        state,
        player_id,
        source_id,
        target_id,
        attachment_id
      )
    end
  end

  defp reduce(state, %Action{
         type: :night_stretcher,
         player_id: player_id,
         params: %{instance_id: stretcher_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, stretcher} <- find_in_player_zone(state, player_id, :hand, stretcher_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(stretcher, "ASC-196"),
         {:ok, target} <- find_in_player_zone(state, player_id, :discard, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_night_stretcher_target(target_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, stretcher, %{}) do
      move_discard_card_to_hand(state, player_id, target)
    end
  end

  defp reduce(state, %Action{
         type: :poke_pad,
         player_id: player_id,
         params: %{instance_id: poke_pad_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, poke_pad} <- find_in_player_zone(state, player_id, :hand, poke_pad_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(poke_pad, "POR-081"),
         {:ok, target} <- find_in_player_zone(state, player_id, :deck, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_non_rule_box_pokemon(target_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, poke_pad, %{}) do
      move_deck_card_to_hand(state, player_id, target)
    end
  end

  defp reduce(state, %Action{
         type: :pokegear_3_0,
         player_id: player_id,
         params: %{instance_id: pokegear_id} = params
       }) do
    target_id = Map.get(params, :target_id)

    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, pokegear} <- find_in_player_zone(state, player_id, :hand, pokegear_id),
         {:ok, pokegear_metadata} <- CardRegistry.fetch(pokegear.card_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(pokegear, "SVI-186"),
         {:ok, target} <- optional_deck_card(state, player_id, target_id),
         :ok <-
           require_optional_card_in_top_deck(
             state,
             player_id,
             target,
             pokegear_metadata.effect.count,
             :pokegear_3_0
           ),
         {:ok, target_metadata} <- optional_card_metadata(target),
         :ok <- require_optional_supporter(target_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, pokegear, %{}) do
      case target do
        nil -> {:ok, state}
        target -> move_deck_card_to_hand(state, player_id, target)
      end
    end
  end

  defp reduce(state, %Action{
         type: :bug_catching_set,
         player_id: player_id,
         params: %{instance_id: bug_catching_set_id} = params
       }) do
    target_ids = Map.get(params, :target_ids, [])

    with true <- is_list(target_ids) || {:error, :bug_catching_set_targets_must_be_list},
         :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, bug_catching_set} <-
           find_in_player_zone(state, player_id, :hand, bug_catching_set_id),
         {:ok, bug_catching_set_metadata} <- CardRegistry.fetch(bug_catching_set.card_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(bug_catching_set, "TWM-143"),
         :ok <-
           require_max_target_ids(
             target_ids,
             bug_catching_set_metadata.effect.max_targets,
             :bug_catching_set
           ),
         :ok <- require_unique_target_ids(target_ids, :bug_catching_set),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <-
           require_cards_in_top_deck(
             state,
             player_id,
             targets,
             bug_catching_set_metadata.effect.count,
             :bug_catching_set
           ),
         :ok <- require_bug_catching_set_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, bug_catching_set, %{}) do
      move_deck_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :team_rockets_transceiver,
         player_id: player_id,
         params: %{instance_id: transceiver_id} = params
       }) do
    target_id = Map.get(params, :target_id)

    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, transceiver} <- find_in_player_zone(state, player_id, :hand, transceiver_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(transceiver, "DRI-178"),
         {:ok, target} <- optional_deck_card(state, player_id, target_id),
         :ok <- require_optional_team_rocket_supporter_target(target),
         {:ok, state} <- discard_card_from_hand(state, player_id, transceiver, %{}) do
      case target do
        nil -> {:ok, state}
        target -> move_deck_card_to_hand(state, player_id, target)
      end
    end
  end

  defp reduce(state, %Action{
         type: :secret_box,
         player_id: player_id,
         params: %{instance_id: secret_box_id, discard_ids: discard_ids} = params
       })
       when is_list(discard_ids) do
    target_ids_by_type = Map.get(params, :target_ids, %{})

    with true <- is_map(target_ids_by_type) || {:error, :secret_box_target_ids_must_be_map},
         :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         true <-
           length(discard_ids) == 3 ||
             {:error, {:wrong_secret_box_discard_count, length(discard_ids)}},
         :ok <- require_unique_target_ids(discard_ids, :secret_box_discard),
         {:ok, secret_box} <- find_in_player_zone(state, player_id, :hand, secret_box_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(secret_box, "TWM-163"),
         :ok <- require_secret_box_discards_other_cards(secret_box_id, discard_ids),
         {:ok, discard_cards} <- fetch_hand_cards(state, player_id, discard_ids),
         :ok <- require_secret_box_target_keys(target_ids_by_type),
         :ok <- require_unique_target_ids(secret_box_target_ids(target_ids_by_type), :secret_box),
         {:ok, targets} <- fetch_secret_box_targets(state, player_id, target_ids_by_type),
         :ok <- require_secret_box_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, secret_box, %{}),
         {:ok, state} <- discard_hand_cards(state, player_id, discard_cards) do
      targets
      |> Enum.map(fn {_trainer_type, card} -> card end)
      |> then(&move_deck_cards_to_hand(state, player_id, &1))
    end
  end

  defp reduce(state, %Action{
         type: :team_rockets_proton,
         player_id: player_id,
         params: %{instance_id: proton_id} = params
       }) do
    target_ids = Map.get(params, :target_ids, [])

    with true <- is_list(target_ids) || {:error, :team_rockets_proton_targets_must_be_list},
         :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, proton} <- find_in_player_zone(state, player_id, :hand, proton_id),
         {:ok, proton_metadata} <- CardRegistry.fetch(proton.card_id),
         :ok <- require_card_id(proton, "DRI-177"),
         :ok <-
           require_team_rockets_proton_supporter_available(proton_metadata, state, player_id),
         :ok <-
           require_max_target_ids(
             target_ids,
             proton_metadata.effect.max_targets,
             :team_rockets_proton
           ),
         :ok <- require_unique_target_ids(target_ids, :team_rockets_proton),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <- require_basic_team_rocket_pokemon_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, proton, proton_metadata) do
      move_deck_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :team_rockets_ariana,
         player_id: player_id,
         params: %{instance_id: ariana_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, ariana} <- find_in_player_zone(state, player_id, :hand, ariana_id),
         {:ok, ariana_metadata} <- CardRegistry.fetch(ariana.card_id),
         :ok <- require_card_id(ariana, "DRI-171"),
         :ok <- require_supporter_available_if_supporter(ariana_metadata, state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, ariana, ariana_metadata) do
      hand_size =
        if all_own_pokemon_in_play_are_team_rocket?(state, player_id) do
          ariana_metadata.effect.team_rocket_hand_size
        else
          ariana_metadata.effect.hand_size
        end

      draw_until_hand_size(state, player_id, hand_size)
    end
  end

  defp reduce(state, %Action{
         type: :team_rockets_archer,
         player_id: player_id,
         params: %{instance_id: archer_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_team_rocket_pokemon_knocked_out_during_opponents_last_turn(player),
         {:ok, archer} <- find_in_player_zone(state, player_id, :hand, archer_id),
         {:ok, archer_metadata} <- CardRegistry.fetch(archer.card_id),
         :ok <- require_card_id(archer, "DRI-170"),
         :ok <- require_supporter_available_if_supporter(archer_metadata, state, player_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, archer, archer_metadata),
         {:ok, state} <- shuffle_hand_into_deck(state, player_id),
         {:ok, state} <- shuffle_hand_into_deck(state, opponent_id),
         {:ok, state} <- draw_cards(state, player_id, archer_metadata.effect.player_draw) do
      draw_cards(state, opponent_id, archer_metadata.effect.opponent_draw)
    end
  end

  defp reduce(state, %Action{
         type: :team_rockets_giovanni,
         player_id: player_id,
         params: %{instance_id: giovanni_id, bench_id: bench_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, giovanni} <- find_in_player_zone(state, player_id, :hand, giovanni_id),
         {:ok, giovanni_metadata} <- CardRegistry.fetch(giovanni.card_id),
         :ok <- require_card_id(giovanni, "DRI-174"),
         :ok <- require_supporter_available_if_supporter(giovanni_metadata, state, player_id),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_active_pokemon(player_id, player),
         :ok <- require_team_rocket_pokemon_for_giovanni(player.active, :active),
         {:ok, bench_card} <- find_in_player_zone(state, player_id, :bench, bench_id),
         :ok <- require_team_rocket_pokemon_for_giovanni(bench_card, :bench),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, target} <- find_in_player_zone(state, opponent_id, :bench, target_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, giovanni, giovanni_metadata),
         {:ok, state} <-
           switch_own_bench_to_active(state, player_id, bench_card, retreated?: false) do
      switch_opponent_bench_to_active(state, opponent_id, target)
    end
  end

  defp reduce(state, %Action{type: :team_rockets_factory, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         :ok <- require_stadium_in_play(state, "DRI-173"),
         {:ok, factory_metadata} <- CardRegistry.fetch("DRI-173"),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_team_rocket_supporter_played_this_turn(player),
         :ok <- require_marker_available(player, {:stadium_used, :team_rockets_factory}),
         {:ok, state} <- draw_cards(state, player_id, factory_metadata.effect.count) do
      put_player_marker(state, player_id, {:stadium_used, :team_rockets_factory})
    end
  end

  defp reduce(state, %Action{
         type: :ciphermaniacs_codebreaking,
         player_id: player_id,
         params: %{instance_id: ciphermaniac_id, target_ids: target_ids}
       })
       when is_list(target_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, ciphermaniac} <- find_in_player_zone(state, player_id, :hand, ciphermaniac_id),
         {:ok, ciphermaniac_metadata} <- CardRegistry.fetch(ciphermaniac.card_id),
         :ok <- require_card_id(ciphermaniac, "TEF-145"),
         :ok <- require_supporter_available_if_supporter(ciphermaniac_metadata, state, player_id),
         :ok <-
           require_exact_target_ids(
             target_ids,
             ciphermaniac_metadata.effect.count,
             :ciphermaniacs_codebreaking
           ),
         :ok <- require_unique_target_ids(target_ids, :ciphermaniacs_codebreaking),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         {:ok, state} <-
           discard_card_from_hand(state, player_id, ciphermaniac, ciphermaniac_metadata) do
      move_deck_cards_to_top(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :cyrano,
         player_id: player_id,
         params: %{instance_id: cyrano_id} = params
       }) do
    target_ids = Map.get(params, :target_ids, [])

    with true <- is_list(target_ids) || {:error, :cyrano_targets_must_be_list},
         :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, cyrano} <- find_in_player_zone(state, player_id, :hand, cyrano_id),
         {:ok, cyrano_metadata} <- CardRegistry.fetch(cyrano.card_id),
         :ok <- require_card_id(cyrano, "SSP-170"),
         :ok <- require_supporter_available_if_supporter(cyrano_metadata, state, player_id),
         :ok <- require_max_target_ids(target_ids, cyrano_metadata.effect.max_targets, :cyrano),
         :ok <- require_unique_target_ids(target_ids, :cyrano),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <- require_pokemon_ex_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, cyrano, cyrano_metadata) do
      move_deck_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :black_belts_training,
         player_id: player_id,
         params: %{instance_id: black_belt_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, black_belt} <- find_in_player_zone(state, player_id, :hand, black_belt_id),
         {:ok, black_belt_metadata} <- CardRegistry.fetch(black_belt.card_id),
         :ok <- require_card_id(black_belt, "JTG-143"),
         :ok <- require_supporter_available_if_supporter(black_belt_metadata, state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, black_belt, black_belt_metadata) do
      put_player_marker(
        state,
        player_id,
        {:damage_bonus_to_opponent_active_pokemon_ex, :black_belts_training}
      )
    end
  end

  defp reduce(state, %Action{
         type: :kieran,
         player_id: player_id,
         params: %{instance_id: kieran_id, choice: :switch, bench_id: bench_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, kieran} <- find_in_player_zone(state, player_id, :hand, kieran_id),
         {:ok, kieran_metadata} <- CardRegistry.fetch(kieran.card_id),
         :ok <- require_card_id(kieran, "TWM-154"),
         :ok <- require_supporter_available_if_supporter(kieran_metadata, state, player_id),
         {:ok, bench_card} <- find_in_player_zone(state, player_id, :bench, bench_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, kieran, kieran_metadata) do
      switch_own_bench_to_active(state, player_id, bench_card, retreated?: false)
    end
  end

  defp reduce(state, %Action{
         type: :kieran,
         player_id: player_id,
         params: %{instance_id: kieran_id, choice: :damage_bonus}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, kieran} <- find_in_player_zone(state, player_id, :hand, kieran_id),
         {:ok, kieran_metadata} <- CardRegistry.fetch(kieran.card_id),
         :ok <- require_card_id(kieran, "TWM-154"),
         :ok <- require_supporter_available_if_supporter(kieran_metadata, state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, kieran, kieran_metadata) do
      put_player_marker(
        state,
        player_id,
        {:damage_bonus_to_opponent_active_pokemon_ex_or_v, :kieran}
      )
    end
  end

  defp reduce(state, %Action{
         type: :wallys_compassion,
         player_id: player_id,
         params: %{instance_id: wally_id, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, wally} <- find_in_player_zone(state, player_id, :hand, wally_id),
         {:ok, wally_metadata} <- CardRegistry.fetch(wally.card_id),
         :ok <- require_card_id(wally, "MEG-132"),
         :ok <- require_supporter_available_if_supporter(wally_metadata, state, player_id),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         {:ok, target_metadata} <- Metadata.fetch(target.card_id),
         :ok <- require_mega_evolution_pokemon_ex(target_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, wally, wally_metadata) do
      if target.damage > 0 do
        with {:ok, state} <- heal_all_pokemon_damage(state, player_id, target_id) do
          return_attached_energy_to_hand(state, player_id, target_id)
        end
      else
        {:ok, state}
      end
    end
  end

  defp reduce(state, %Action{
         type: :dawn,
         player_id: player_id,
         params: %{
           instance_id: dawn_id,
           basic_id: basic_id,
           stage_1_id: stage_1_id,
           stage_2_id: stage_2_id
         }
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, dawn} <- find_in_player_zone(state, player_id, :hand, dawn_id),
         {:ok, dawn_metadata} <- CardRegistry.fetch(dawn.card_id),
         :ok <- require_card_id(dawn, "PFL-087"),
         :ok <- require_supporter_available_if_supporter(dawn_metadata, state, player_id),
         {:ok, targets} <- fetch_deck_cards(state, player_id, [basic_id, stage_1_id, stage_2_id]),
         :ok <- require_pokemon_stage(Enum.at(targets, 0), :basic),
         :ok <- require_pokemon_stage(Enum.at(targets, 1), :stage_1),
         :ok <- require_pokemon_stage(Enum.at(targets, 2), :stage_2),
         {:ok, state} <- discard_card_from_hand(state, player_id, dawn, dawn_metadata) do
      move_deck_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :sacred_ash,
         player_id: player_id,
         params: %{instance_id: sacred_ash_id, target_ids: target_ids}
       })
       when is_list(target_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         true <-
           length(target_ids) == 5 ||
             {:error, {:sacred_ash_requires_five_targets, length(target_ids)}},
         {:ok, sacred_ash} <- find_in_player_zone(state, player_id, :hand, sacred_ash_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_card_id(sacred_ash, "DRI-168"),
         {:ok, targets} <- fetch_discard_cards(state, player_id, target_ids),
         :ok <- require_all_pokemon(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, sacred_ash, %{}) do
      move_discard_cards_to_deck(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{type: :judge, player_id: player_id, params: %{instance_id: judge_id}}) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, judge} <- find_in_player_zone(state, player_id, :hand, judge_id),
         {:ok, judge_metadata} <- CardRegistry.fetch(judge.card_id),
         :ok <- require_card_id(judge, "POR-076"),
         :ok <- require_supporter_available_if_supporter(judge_metadata, state, player_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, judge, judge_metadata),
         {:ok, state} <- shuffle_hand_into_deck(state, player_id),
         {:ok, state} <- shuffle_hand_into_deck(state, opponent_id),
         {:ok, state} <- draw_cards(state, player_id, 4) do
      draw_cards(state, opponent_id, 4)
    end
  end

  defp reduce(state, %Action{
         type: :hilda,
         player_id: player_id,
         params: %{instance_id: hilda_id, evolution_id: evolution_id, energy_id: energy_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, hilda} <- find_in_player_zone(state, player_id, :hand, hilda_id),
         {:ok, hilda_metadata} <- CardRegistry.fetch(hilda.card_id),
         :ok <- require_card_id(hilda, "WHT-084"),
         :ok <- require_supporter_available_if_supporter(hilda_metadata, state, player_id),
         {:ok, targets} <- fetch_deck_cards(state, player_id, [evolution_id, energy_id]),
         :ok <- require_evolution_pokemon(Enum.at(targets, 0)),
         {:ok, energy_metadata} <- CardRegistry.fetch(Enum.at(targets, 1).card_id),
         :ok <- require_energy(energy_metadata),
         {:ok, state} <- discard_card_from_hand(state, player_id, hilda, hilda_metadata) do
      move_deck_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(state, %Action{
         type: :lanas_aid,
         player_id: player_id,
         params: %{instance_id: lana_id, target_ids: target_ids}
       })
       when is_list(target_ids) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         true <-
           length(target_ids) <= 3 || {:error, {:too_many_lanas_aid_targets, length(target_ids)}},
         {:ok, lana} <- find_in_player_zone(state, player_id, :hand, lana_id),
         {:ok, lana_metadata} <- CardRegistry.fetch(lana.card_id),
         :ok <- require_card_id(lana, "TWM-155"),
         :ok <- require_supporter_available_if_supporter(lana_metadata, state, player_id),
         {:ok, targets} <- fetch_discard_cards(state, player_id, target_ids),
         :ok <- require_lanas_aid_targets(targets),
         {:ok, state} <- discard_card_from_hand(state, player_id, lana, lana_metadata) do
      move_discard_cards_to_hand(state, player_id, targets)
    end
  end

  defp reduce(
         state,
         %Action{
           type: :crispin,
           player_id: player_id,
           params: %{instance_id: crispin_id, hand_energy_id: hand_energy_id}
         } =
           action
       ) do
    attach_energy_id = Map.get(action.params, :attach_energy_id)
    target_id = Map.get(action.params, :target_id)

    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, crispin} <- find_in_player_zone(state, player_id, :hand, crispin_id),
         {:ok, crispin_metadata} <- CardRegistry.fetch(crispin.card_id),
         :ok <- require_card_id(crispin, "SCR-133"),
         :ok <- require_supporter_available_if_supporter(crispin_metadata, state, player_id),
         {:ok, hand_energy} <- find_in_player_zone(state, player_id, :deck, hand_energy_id),
         {:ok, hand_energy_metadata} <- CardRegistry.fetch(hand_energy.card_id),
         :ok <- require_basic_energy(hand_energy_metadata),
         {:ok, attach_energy} <- optional_deck_card(state, player_id, attach_energy_id),
         {:ok, attach_energy_metadata} <- optional_card_metadata(attach_energy),
         :ok <- require_optional_basic_energy(attach_energy_metadata),
         :ok <- require_different_energy_types(hand_energy_metadata, attach_energy_metadata),
         {:ok, target} <- optional_in_play_target(state, player_id, target_id, attach_energy),
         {:ok, state} <- discard_card_from_hand(state, player_id, crispin, crispin_metadata),
         {:ok, state} <- move_deck_card_to_hand(state, player_id, hand_energy) do
      case attach_energy do
        nil -> {:ok, state}
        attach_energy -> attach_deck_energy_to_pokemon(state, player_id, attach_energy, target)
      end
    end
  end

  defp reduce(state, %Action{
         type: :lillies_determination,
         player_id: player_id,
         params: %{instance_id: lillie_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, lillie} <- find_in_player_zone(state, player_id, :hand, lillie_id),
         {:ok, lillie_metadata} <- CardRegistry.fetch(lillie.card_id),
         :ok <- require_card_id(lillie, "MEG-119"),
         :ok <- require_supporter_available_if_supporter(lillie_metadata, state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, lillie, lillie_metadata),
         {:ok, state} <- shuffle_hand_into_deck(state, player_id) do
      draw_count = if length(state.players[player_id].prizes) == 6, do: 8, else: 6
      draw_cards(state, player_id, draw_count)
    end
  end

  defp reduce(state, %Action{
         type: :unfair_stamp,
         player_id: player_id,
         params: %{instance_id: stamp_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_pokemon_knocked_out_during_opponents_last_turn(player),
         {:ok, stamp} <- find_in_player_zone(state, player_id, :hand, stamp_id),
         :ok <- require_item_cards_playable(state, player_id),
         :ok <- require_ace_spec_cards_playable(state, player_id),
         :ok <- require_card_id(stamp, "TWM-165"),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, state} <- discard_card_from_hand(state, player_id, stamp, %{}),
         {:ok, state} <- shuffle_hand_into_deck(state, player_id),
         {:ok, state} <- shuffle_hand_into_deck(state, opponent_id),
         {:ok, state} <- draw_cards(state, player_id, 5) do
      draw_cards(state, opponent_id, 2)
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :recon_directive, chosen_id: chosen_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, _ability} <- require_ability(state, source, :recon_directive),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :recon_directive}),
         {:ok, chosen, other} <- require_top_two_choice(player, chosen_id) do
      chosen = %{chosen | zone: :hand, lifecycle: :in_hand}
      other = %{other | zone: :deck, lifecycle: :in_deck}

      player = %{
        player
        | deck: Enum.drop(player.deck, 2) ++ [other],
          hand: [chosen | player.hand],
          markers: MapSet.put(player.markers, {:ability_used, source_id, :recon_directive})
      }

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :boom_boom_groove} = params
       }) do
    target_id = Map.get(params, :target_id)

    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, _ability} <- require_ability(state, source, :boom_boom_groove),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :boom_boom_groove}),
         :ok <- require_active_pokemon_has_festival_lead_ability(state, player_id),
         {:ok, target} <- optional_deck_card(state, player_id, target_id),
         {:ok, state} <- move_optional_deck_card_to_hand(state, player_id, target),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{
        player
        | markers: MapSet.put(player.markers, {:ability_used, source_id, :boom_boom_groove})
      }

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :fan_call} = params
       }) do
    target_ids = Map.get(params, :target_ids, [])

    with true <- is_list(target_ids) || {:error, :fan_call_targets_must_be_list},
         :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :fan_call),
         :ok <- require_player_first_turn(state, player_id, :fan_call),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, :fan_call}),
         :ok <- require_max_target_ids(target_ids, ability.effect.max_targets, :fan_call),
         :ok <- require_unique_target_ids(target_ids, :fan_call),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <- require_colorless_pokemon_with_100_hp_or_less_targets(targets),
         {:ok, state} <- move_deck_cards_to_hand(state, player_id, targets),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{player | markers: MapSet.put(player.markers, {:ability_used, :fan_call})}
      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :psychic_draw}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :psychic_draw),
         :ok <- require_evolved_this_turn(state, source),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :psychic_draw}) do
      with {:ok, state} <- draw_cards(state, player_id, ability.effect.count),
           {:ok, player} <- fetch_player(state, player_id) do
        player = %{
          player
          | markers: MapSet.put(player.markers, {:ability_used, source_id, :psychic_draw})
        }

        {:ok, put_player(state, player)}
      end
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :run_errand}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, source} <- require_active_source(player, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :run_errand),
         :ok <- require_marker_available(player, {:ability_used, :run_errand}),
         {:ok, state} <- draw_cards(state, player_id, ability.effect.count),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{player | markers: MapSet.put(player.markers, {:ability_used, :run_errand})}
      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :run_away_draw}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :run_away_draw),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :run_away_draw}),
         {:ok, state} <- draw_cards(state, player_id, ability.effect.count),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, source} <- find_in_play(state, player_id, source_id) do
      shuffled_cards = reset_tree_for_deck(source)

      player =
        player
        |> remove_in_play(source.instance_id)
        |> Map.update!(:deck, &(shuffled_cards ++ &1))
        |> Map.update!(:markers, &MapSet.put(&1, {:ability_used, source_id, :run_away_draw}))

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :teleporter}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, source} <- require_active_source(player, player_id, source_id),
         {:ok, _ability} <- require_ability(state, source, :teleporter),
         :ok <- require_marker_available(player, {:ability_used, source_id, :teleporter}) do
      shuffled_cards = reset_tree_for_deck(source)

      player =
        player
        |> remove_in_play(source.instance_id)
        |> Map.update!(:deck, &(shuffled_cards ++ &1))
        |> Map.update!(:markers, &MapSet.put(&1, {:ability_used, source_id, :teleporter}))

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{
           source_id: source_id,
           ability_id: :adrena_brain,
           from_id: from_id,
           target_player_id: target_player_id,
           target_id: target_id,
           counters: counters
         }
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :adrena_brain),
         :ok <- require_attached_energy_type(source, ability.effect.requires_attached_type),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :adrena_brain}),
         :ok <- require_counter_count(counters, ability.effect.max_counters),
         {:ok, damaged_from} <- find_in_play(state, player_id, from_id),
         :ok <- require_available_damage_counters(damaged_from, counters),
         {:ok, _target} <- find_in_play(state, target_player_id, target_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         :ok <- require_same_player(target_player_id, opponent_id),
         {:ok, state} <-
           move_damage_counters(state, player_id, from_id, target_player_id, target_id, counters),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, state} <-
           resolve_knock_outs_after_damage(state, player_id, target_player_id, target_id) do
      player = %{
        player
        | markers: MapSet.put(player.markers, {:ability_used, source_id, :adrena_brain})
      }

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :flip_the_script}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, ability} <- require_ability(state, source, :flip_the_script),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_pokemon_knocked_out_during_opponents_last_turn(player),
         :ok <- require_marker_available(player, {:ability_used, :flip_the_script}),
         {:ok, state} <- draw_cards(state, player_id, ability.effect.count),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{player | markers: MapSet.put(player.markers, {:ability_used, :flip_the_script})}
      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :last_ditch_catch, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_player_zone(state, player_id, :bench, source_id),
         {:ok, _ability} <- require_ability(state, source, :last_ditch_catch),
         :ok <- require_played_this_turn(state, source),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, :last_ditch}),
         {:ok, target} <- find_in_player_zone(state, player_id, :deck, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_supporter(target_metadata),
         {:ok, state} <- move_deck_card_to_hand(state, player_id, target),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{player | markers: MapSet.put(player.markers, {:ability_used, :last_ditch})}
      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{
         type: :use_ability,
         player_id: player_id,
         params: %{source_id: source_id, ability_id: :charging_up, target_id: target_id}
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, _ability} <- require_ability(state, source, :charging_up),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_marker_available(player, {:ability_used, source_id, :charging_up}),
         {:ok, target} <- find_in_player_zone(state, player_id, :discard, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_basic_energy(target_metadata),
         {:ok, state} <- attach_discard_energy_to_pokemon(state, player_id, target, source),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{
        player
        | markers: MapSet.put(player.markers, {:ability_used, source_id, :charging_up})
      }

      {:ok, put_player(state, player)}
    end
  end

  defp reduce(state, %Action{type: :draw_cards, player_id: player_id, params: %{count: count}})
       when is_integer(count) and count >= 0 do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_turn_lifecycle(state, :action_window) do
      draw_cards(state, player_id, count)
    end
  end

  defp reduce(state, %Action{type: :declare_attack, player_id: player_id, params: params})
       when params == %{} do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_game_lifecycle(state, :in_progress),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_active_pokemon(player_id, player),
         :ok <- require_can_attack(player.active),
         :ok <- require_first_player_can_attack(state, player_id),
         {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :declare_attack),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :declare_attack) do
      {:ok,
       %{
         state
         | game_lifecycle: game_lifecycle,
           turn_lifecycle: turn_lifecycle,
           log: ["#{player_id} declared an attack" | state.log]
       }}
    end
  end

  defp reduce(state, %Action{
         type: :declare_attack,
         player_id: player_id,
         params: %{attack_id: attack_id} = params
       }) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_game_lifecycle(state, :in_progress),
         :ok <- require_turn_lifecycle(state, :action_window),
         {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_active_pokemon(player_id, player),
         :ok <- require_can_attack(player.active),
         :ok <- require_first_player_can_attack(state, player_id),
         {:ok, attack} <- CardRegistry.fetch_attack(player.active.card_id, attack_id),
         :ok <- require_attack_cost(state, player_id, player.active, attack),
         :ok <- require_confusion_result(player.active, params),
         {:ok, defender_id} <- opponent_id(state, player_id),
         {:ok, defender} <- fetch_player(state, defender_id),
         :ok <- require_active_pokemon(defender_id, defender),
         :ok <- require_attack_effect_params(attack, params, defender),
         {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :declare_attack),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :declare_attack) do
      pending_attack = %{
        player_id: player_id,
        attacker_id: player.active.instance_id,
        attack_id: attack_id,
        attack: attack,
        params: Map.delete(params, :attack_id),
        attacker_status: player.active.status,
        target_player_id: defender_id,
        target_id: defender.active.instance_id
      }

      {:ok,
       %{
         state
         | game_lifecycle: game_lifecycle,
           turn_lifecycle: turn_lifecycle,
           pending_attack: pending_attack,
           log: ["#{player_id} declared #{attack.name}" | state.log]
       }}
    end
  end

  defp reduce(state, %Action{type: :resolve_declared_attack, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_game_lifecycle(state, :resolving_attack),
         {:ok, pending_attack} <- fetch_pending_attack(state, player_id),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :resolve_attack) do
      case resolve_confusion_check(state, pending_attack) do
        {:ok, state} ->
          with {:ok, damage} <- attack_damage(state, pending_attack),
               {:ok, state, damage_result} <-
                 damage_active_pokemon_from_attack(state, pending_attack, damage),
               {:ok, state} <-
                 maybe_run_after_attack_damage_hooks(state, pending_attack, damage, damage_result),
               {:ok, state} <-
                 maybe_resolve_knock_outs_after_attack_damage(
                   state,
                   pending_attack,
                   damage_result
                 ),
               {:ok, state} <- resolve_attack_effect(state, pending_attack) do
            {:ok, %{state | turn_lifecycle: turn_lifecycle, pending_attack: nil}}
          end

        {:confused_tails, state} ->
          {:ok, %{state | turn_lifecycle: turn_lifecycle, pending_attack: nil}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp reduce(state, %Action{
         type: :resolve_attack_damage,
         player_id: player_id,
         params: %{target_player_id: target_player_id, target_id: target_id, damage: damage}
       })
       when is_integer(damage) and damage >= 0 do
    with :ok <- require_active_player(state, player_id),
         :ok <- require_game_lifecycle(state, :resolving_attack),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :resolve_attack),
         {:ok, state} <- damage_pokemon(state, target_player_id, target_id, damage),
         {:ok, state} <-
           resolve_knock_outs_after_damage(state, player_id, target_player_id, target_id) do
      {:ok, %{state | turn_lifecycle: turn_lifecycle}}
    end
  end

  defp reduce(state, %Action{type: :finish_attack, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :finish_attack),
         {:ok, game_lifecycle} <- finish_attack_game_lifecycle(state.game_lifecycle) do
      {:ok,
       %{
         state
         | game_lifecycle: game_lifecycle,
           turn_lifecycle: turn_lifecycle,
           pending_attack: nil
       }}
    end
  end

  defp reduce(state, %Action{
         type: :choose_prize,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_game_lifecycle(state, :choosing_prizes),
         {:ok, pending_prizes} <- fetch_pending_prizes(state, player_id),
         {:ok, state} <- take_prize(state, player_id, instance_id) do
      remaining = pending_prizes.remaining - 1

      cond do
        state.winner ->
          {:ok, %{state | pending_prizes: nil}}

        remaining > 0 ->
          {:ok, %{state | pending_prizes: %{pending_prizes | remaining: remaining}}}

        true ->
          state
          |> Map.put(:pending_prizes, nil)
          |> finish_prize_resolution_after_choices(
            pending_prizes.player_id,
            pending_prizes.defending_player_id
          )
      end
    end
  end

  defp reduce(state, %Action{
         type: :choose_replacement_active,
         player_id: player_id,
         params: %{instance_id: instance_id}
       }) do
    with :ok <- require_game_lifecycle(state, :replacing_active),
         {:ok, player} <- fetch_player(state, player_id),
         true <- is_nil(player.active) || {:error, {:active_already_present, player_id}},
         {:ok, card} <- find_in_player_zone(state, player_id, :bench, instance_id),
         {:ok, :active} <- ZoneMovement.transition(:bench, :active),
         {:ok, game_lifecycle} <-
           GameLifecycle.transition(state.game_lifecycle, :replacement_chosen) do
      moved = %{card | zone: :active, status: nil}
      player = %{player | active: moved, bench: reject_instance(player.bench, instance_id)}
      {:ok, %{put_player(state, player) | game_lifecycle: game_lifecycle}}
    end
  end

  defp reduce(state, %Action{type: :concede, player_id: player_id}) do
    with :ok <- require_not_finished(state),
         {:ok, winner} <- opponent_id(state, player_id) do
      {:ok,
       %{
         state
         | winner: winner,
           game_lifecycle: :finished,
           log: ["#{player_id} conceded" | state.log]
       }}
    end
  end

  defp reduce(state, %Action{type: :end_turn, player_id: player_id}) do
    with :ok <- require_active_player(state, player_id),
         {:ok, turn_lifecycle} <- end_turn_lifecycle(state.turn_lifecycle),
         {:ok, player} <- fetch_player(state, player_id) do
      player = %{
        player
        | pokemon_knocked_out_during_opponents_last_turn?: false,
          team_rocket_pokemon_knocked_out_during_opponents_last_turn?: false,
          item_cards_locked?: false
      }

      {:ok,
       state
       |> put_player(player)
       |> Map.merge(%{
         turn_lifecycle: turn_lifecycle,
         log: ["#{player_id} ended turn" | state.log]
       })}
    end
  end

  defp reduce(state, %Action{type: :start_next_turn}) do
    with :ok <- require_turn_lifecycle(state, :not_in_turn),
         :ok <- require_game_lifecycle(state, :in_progress),
         {:ok, next_player_id} <- opponent_id(state, state.active_player),
         {:ok, turn_lifecycle} <- TurnLifecycle.transition(state.turn_lifecycle, :start_turn),
         {:ok, next_player} <- fetch_player(state, next_player_id) do
      next_player = reset_turn_flags(next_player)

      {:ok,
       state
       |> put_player(next_player)
       |> Map.merge(%{
         active_player: next_player_id,
         turn_lifecycle: turn_lifecycle,
         turn_number: state.turn_number + 1,
         log: ["#{next_player_id} started turn" | state.log]
       })}
    end
  end

  defp reduce(_state, %Action{type: type}), do: {:error, {:unsupported_action, type}}

  defp instantiate_deck(player_id, deck_ids) do
    deck_ids
    |> Enum.with_index(1)
    |> Enum.map(fn {card_id, index} ->
      CardRegistry.fetch!(card_id)
      %CardInstance{instance_id: "#{player_id}-#{index}", card_id: card_id, owner: player_id}
    end)
  end

  defp draw_card(state, player_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      case player.deck do
        [] ->
          {:error, :cannot_draw_from_empty_deck}

        [card | deck] ->
          with {:ok, :hand} <- ZoneMovement.transition(:deck, :hand),
               {:ok, :in_hand} <- CardLifecycle.transition(card.lifecycle, :draw) do
            card = %{card | zone: :hand, lifecycle: :in_hand}
            player = %{player | deck: deck, hand: [card | player.hand]}
            {:ok, put_player(state, player)}
          end
      end
    end
  end

  defp draw_cards(state, _player_id, 0), do: {:ok, state}

  defp draw_cards(state, player_id, count) when count > 0 do
    with {:ok, state} <- draw_card(state, player_id) do
      draw_cards(state, player_id, count - 1)
    end
  end

  defp draw_until_hand_size(state, player_id, hand_size) when is_integer(hand_size) do
    with {:ok, player} <- fetch_player(state, player_id) do
      draw_cards(state, player_id, max(hand_size - length(player.hand), 0))
    end
  end

  defp place_prizes(state, _player_id, 0), do: {:ok, state}

  defp place_prizes(state, player_id, count) when count > 0 do
    with {:ok, state} <- move_top_deck_card_to_prizes(state, player_id) do
      place_prizes(state, player_id, count - 1)
    end
  end

  defp move_top_deck_card_to_prizes(state, player_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      case player.deck do
        [] ->
          {:error, :cannot_prize_from_empty_deck}

        [card | deck] ->
          with {:ok, :prizes} <- ZoneMovement.transition(:deck, :prizes),
               {:ok, :prized} <- CardLifecycle.transition(card.lifecycle, :prize) do
            card = %{card | zone: :prizes, lifecycle: :prized}
            player = %{player | deck: deck, prizes: [card | player.prizes]}
            {:ok, put_player(state, player)}
          end
      end
    end
  end

  defp choose_active(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved = %{
        card
        | zone: :active,
          lifecycle: :in_play_basic,
          turn_entered_play: state.turn_number
      }

      player = %{player | hand: reject_instance(player.hand, card.instance_id), active: moved}
      {:ok, put_player(state, player)}
    end
  end

  defp move_hand_card_to_bench(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_bench_space(player) do
      moved = %{
        card
        | zone: :bench,
          lifecycle: :in_play_basic,
          turn_entered_play: state.turn_number
      }

      player = %{
        player
        | hand: reject_instance(player.hand, card.instance_id),
          bench: [moved | player.bench]
      }

      state
      |> put_player(player)
      |> apply_risky_ruins_if_needed(player_id, moved)
    end
  end

  defp apply_risky_ruins_if_needed(
         %{game_lifecycle: :in_progress, active_player: player_id, stadium: %{card_id: "MEG-127"}} =
           state,
         player_id,
         pokemon
       ) do
    with {:ok, metadata} <- CardRegistry.fetch(pokemon.card_id) do
      if metadata[:supertype] == :pokemon && metadata[:stage] == :basic &&
           metadata[:type] != :darkness do
        damage_pokemon(state, player_id, pokemon.instance_id, 20)
      else
        {:ok, state}
      end
    end
  end

  defp apply_risky_ruins_if_needed(state, _player_id, _pokemon), do: {:ok, state}

  defp attach_to_pokemon(state, player_id, energy, target, params) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved_energy = %{energy | zone: :attached, lifecycle: :attached}

      updated_target =
        target
        |> Map.put(:attachments, [moved_energy | target.attachments])
        |> recover_special_condition_if_festival_grounds_active(state)

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:hand, &reject_instance(&1, energy.instance_id))
        |> Map.put(:energy_attached?, true)

      state = put_player(state, player)
      apply_attachment_effect(state, player_id, moved_energy, updated_target, params)
    end
  end

  defp attach_deck_energy_to_pokemon(state, player_id, energy, target) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved_energy = %{energy | zone: :attached, lifecycle: :attached}

      updated_target =
        target
        |> Map.put(:attachments, [moved_energy | target.attachments])
        |> recover_special_condition_if_festival_grounds_active(state)

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:deck, &reject_instance(&1, energy.instance_id))

      {:ok, put_player(state, player)}
    end
  end

  defp attach_discard_energy_to_pokemon(state, player_id, energy, target) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, :attached} <- ZoneMovement.transition(:discard, :attached),
         {:ok, :attached} <- CardLifecycle.transition(energy.lifecycle, :attach) do
      moved_energy = %{energy | zone: :attached, lifecycle: :attached}

      updated_target =
        target
        |> Map.put(:attachments, [moved_energy | target.attachments])
        |> recover_special_condition_if_festival_grounds_active(state)

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:discard, &reject_instance(&1, energy.instance_id))

      {:ok, put_player(state, player)}
    end
  end

  defp evolve_pokemon(state, player_id, evolution_card, target) do
    with {:ok, player} <- fetch_player(state, player_id) do
      evolved = %{
        evolution_card
        | zone: target.zone,
          lifecycle: :in_play_evolved,
          attachments: target.attachments,
          damage: target.damage,
          status: nil,
          tool: target.tool,
          evolved_from: [
            %{target | attachments: [], tool: nil, evolved_from: []} | target.evolved_from
          ],
          turn_entered_play: state.turn_number
      }

      player =
        player
        |> replace_in_play(target, evolved)
        |> Map.update!(:hand, &reject_instance(&1, evolution_card.instance_id))

      {:ok, put_player(state, player)}
    end
  end

  defp discard_card_from_hand(state, player_id, card, metadata) do
    with {:ok, player} <- fetch_player(state, player_id) do
      discarded = %{card | zone: :discard, lifecycle: :discarded}

      player =
        mark_team_rocket_supporter_played(
          %{
            player
            | hand: reject_instance(player.hand, card.instance_id),
              discard: [discarded | player.discard],
              supporter_played?:
                player.supporter_played? || Map.get(metadata, :trainer_type) == :supporter
          },
          metadata
        )

      {:ok, put_player(state, player)}
    end
  end

  defp mark_team_rocket_supporter_played(player, metadata) do
    if team_rocket_supporter?(metadata) do
      %{player | markers: MapSet.put(player.markers, :team_rocket_supporter_played_this_turn)}
    else
      player
    end
  end

  defp team_rocket_supporter?(%{trainer_type: :supporter, name: name}) when is_binary(name),
    do: String.contains?(name, "Team Rocket")

  defp team_rocket_supporter?(_metadata), do: false

  defp discard_card_from_deck(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      discarded = %{card | zone: :discard, lifecycle: :discarded}

      player = %{
        player
        | deck: reject_instance(player.deck, card.instance_id),
          discard: [discarded | player.discard]
      }

      {:ok, put_player(state, player)}
    end
  end

  defp play_stadium_card(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      stadium = %{card | zone: :stadium, lifecycle: :in_stadium}
      player = %{player | hand: reject_instance(player.hand, card.instance_id)}
      state = put_player(state, player)

      state =
        case state.stadium do
          nil -> state
          old_stadium -> discard_stadium(state, old_stadium)
        end

      state = %{state | stadium: stadium}

      {:ok, recover_special_conditions_from_festival_grounds(state)}
    end
  end

  defp discard_stadium(state, stadium) do
    discarded = %{stadium | zone: :discard, lifecycle: :discarded}

    update_in(state.players[stadium.owner].discard, fn discard ->
      [discarded | discard]
    end)
  end

  defp attach_tool_to_pokemon(state, player_id, tool, target) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved_tool = %{tool | zone: :attached, lifecycle: :attached}
      updated_target = %{target | tool: moved_tool}

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:hand, &reject_instance(&1, tool.instance_id))

      {:ok, put_player(state, player)}
    end
  end

  defp move_deck_card_to_hand(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved = %{card | zone: :hand, lifecycle: :in_hand}

      player = %{
        player
        | deck: reject_instance(player.deck, card.instance_id),
          hand: [moved | player.hand]
      }

      {:ok, put_player(state, player)}
    end
  end

  defp move_optional_deck_card_to_hand(state, _player_id, nil), do: {:ok, state}

  defp move_optional_deck_card_to_hand(state, player_id, card),
    do: move_deck_card_to_hand(state, player_id, card)

  defp move_deck_cards_to_hand(state, _player_id, []), do: {:ok, state}

  defp move_deck_cards_to_hand(state, player_id, [card | rest]) do
    with {:ok, state} <- move_deck_card_to_hand(state, player_id, card) do
      move_deck_cards_to_hand(state, player_id, rest)
    end
  end

  defp move_deck_cards_to_top(state, player_id, cards) do
    with {:ok, player} <- fetch_player(state, player_id) do
      chosen_instance_ids = MapSet.new(cards, & &1.instance_id)

      remaining_deck =
        Enum.reject(player.deck, &MapSet.member?(chosen_instance_ids, &1.instance_id))

      player = %{player | deck: cards ++ remaining_deck}

      {:ok, put_player(state, player)}
    end
  end

  defp move_discard_card_to_hand(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved = %{card | zone: :hand, lifecycle: :in_hand}

      player = %{
        player
        | discard: reject_instance(player.discard, card.instance_id),
          hand: [moved | player.hand]
      }

      {:ok, put_player(state, player)}
    end
  end

  defp move_discard_cards_to_hand(state, _player_id, []), do: {:ok, state}

  defp move_discard_cards_to_hand(state, player_id, [card | rest]) do
    with {:ok, state} <- move_discard_card_to_hand(state, player_id, card) do
      move_discard_cards_to_hand(state, player_id, rest)
    end
  end

  defp move_discard_card_to_deck(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved = %{card | zone: :deck, lifecycle: :in_deck}

      player = %{
        player
        | discard: reject_instance(player.discard, card.instance_id),
          deck: [moved | player.deck]
      }

      {:ok, put_player(state, player)}
    end
  end

  defp move_discard_cards_to_deck(state, _player_id, []), do: {:ok, state}

  defp move_discard_cards_to_deck(state, player_id, [card | rest]) do
    with {:ok, state} <- move_discard_card_to_deck(state, player_id, card) do
      move_discard_cards_to_deck(state, player_id, rest)
    end
  end

  defp shuffle_hand_into_deck(state, player_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      moved_hand = Enum.map(player.hand, &%{&1 | zone: :deck, lifecycle: :in_deck})
      player = %{player | hand: [], deck: player.deck ++ moved_hand}
      {:ok, put_player(state, player)}
    end
  end

  defp move_deck_card_to_bench(state, player_id, card) do
    with {:ok, player} <- fetch_player(state, player_id),
         :ok <- require_bench_space(player) do
      moved = %{
        card
        | zone: :bench,
          lifecycle: :in_play_basic,
          turn_entered_play: state.turn_number
      }

      player = %{
        player
        | deck: reject_instance(player.deck, card.instance_id),
          bench: [moved | player.bench]
      }

      state
      |> put_player(player)
      |> apply_risky_ruins_if_needed(player_id, moved)
    end
  end

  defp apply_attachment_effect(state, player_id, %{card_id: "POR-088"}, target, %{
         target_ids: target_ids
       }) do
    with {:ok, %{type: :psychic}} <- CardRegistry.fetch(target.card_id),
         {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids),
         :ok <- require_basic_psychic_pokemon_targets(targets) do
      Enum.reduce_while(targets, {:ok, state}, fn target, {:ok, state} ->
        case move_deck_card_to_bench(state, player_id, target) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      {:ok, _non_psychic_target} -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_attachment_effect(state, player_id, %{card_id: "SSP-191"}, _target, _params) do
    draw_cards(state, player_id, 4)
  end

  defp apply_attachment_effect(state, _player_id, _energy, _target, _params), do: {:ok, state}

  defp discard_hand_cards(state, _player_id, []), do: {:ok, state}

  defp discard_hand_cards(state, player_id, [card | rest]) do
    with {:ok, state} <- discard_card_from_hand(state, player_id, card, %{}) do
      discard_hand_cards(state, player_id, rest)
    end
  end

  defp switch_opponent_bench_to_active(state, opponent_id, target) do
    with {:ok, opponent} <- fetch_player(state, opponent_id),
         active when not is_nil(active) <- opponent.active do
      moved_active = %{active | zone: :bench, status: nil}
      moved_target = %{target | zone: :active, status: nil}

      opponent = %{
        opponent
        | active: moved_target,
          bench: [moved_active | reject_instance(opponent.bench, target.instance_id)]
      }

      {:ok, put_player(state, opponent)}
    else
      nil -> {:error, {:missing_active_pokemon, opponent_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp switch_own_bench_to_active(state, player_id, target, opts) do
    with {:ok, player} <- fetch_player(state, player_id),
         active when not is_nil(active) <- player.active do
      moved_active = %{active | zone: :bench, status: nil}
      moved_target = %{target | zone: :active, status: nil}

      player = %{
        player
        | active: moved_target,
          bench: [moved_active | reject_instance(player.bench, target.instance_id)],
          retreated?: opts[:retreated?] || player.retreated?,
          markers:
            MapSet.put(
              player.markers,
              {:moved_from_bench_to_active_this_turn, moved_target.instance_id}
            )
      }

      {:ok, put_player(state, player)}
    else
      nil -> {:error, {:missing_active_pokemon, player_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp discard_attached_card(state, player_id, target, attachment) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, :discard} <- ZoneMovement.transition(:attached, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(attachment.lifecycle, :discard) do
      discarded = %{attachment | zone: :discard, lifecycle: :discarded}

      updated_target = %{
        target
        | attachments: reject_instance(target.attachments, attachment.instance_id)
      }

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:discard, &[discarded | &1])

      {:ok, put_player(state, player)}
    end
  end

  defp discard_attached_cards(state, _player_id, _target, []), do: {:ok, state}

  defp discard_attached_cards(state, player_id, target, [attachment | rest]) do
    with {:ok, state} <- discard_attached_card(state, player_id, target, attachment),
         {:ok, updated_target} <- find_in_play(state, player_id, target.instance_id) do
      discard_attached_cards(state, player_id, updated_target, rest)
    end
  end

  defp move_attached_card_between_own_pokemon(
         state,
         player_id,
         source_id,
         target_id,
         attachment_id
       ) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, source} <- find_in_play(state, player_id, source_id),
         {:ok, target} <- find_in_play(state, player_id, target_id),
         {:ok, attachment} <- find_attachment(source, attachment_id) do
      moved_attachment = %{attachment | zone: :attached, lifecycle: :attached}
      updated_source = %{source | attachments: reject_instance(source.attachments, attachment_id)}

      updated_target =
        target
        |> Map.put(:attachments, [moved_attachment | target.attachments])
        |> recover_special_condition_if_festival_grounds_active(state)

      player =
        player
        |> replace_in_play(updated_source)
        |> replace_in_play(updated_target)

      {:ok, put_player(state, player)}
    end
  end

  defp remove_in_play(player, instance_id) do
    cond do
      player.active && player.active.instance_id == instance_id ->
        %{player | active: nil}

      Enum.any?(player.bench, &(&1.instance_id == instance_id)) ->
        %{player | bench: reject_instance(player.bench, instance_id)}

      true ->
        player
    end
  end

  defp reset_tree_for_deck(nil), do: []

  defp reset_tree_for_deck(card) do
    reset = %{
      card
      | zone: :deck,
        lifecycle: :in_deck,
        damage: 0,
        status: nil,
        tool: nil,
        attachments: [],
        evolved_from: [],
        turn_entered_play: nil
    }

    [reset]
    |> Kernel.++(Enum.flat_map(card.attachments, &reset_tree_for_deck/1))
    |> Kernel.++(reset_tree_for_deck(card.tool))
    |> Kernel.++(Enum.flat_map(card.evolved_from, &reset_tree_for_deck/1))
  end

  defp reset_tree_for_hand(nil), do: []

  defp reset_tree_for_hand(card) do
    reset = %{
      card
      | zone: :hand,
        lifecycle: :in_hand,
        damage: 0,
        status: nil,
        tool: nil,
        attachments: [],
        evolved_from: [],
        turn_entered_play: nil
    }

    [reset]
    |> Kernel.++(Enum.flat_map(card.attachments, &reset_tree_for_hand/1))
    |> Kernel.++(reset_tree_for_hand(card.tool))
    |> Kernel.++(Enum.flat_map(card.evolved_from, &reset_tree_for_hand/1))
  end

  defp return_in_play_tree_to_hand(state, player_id, instance_id) do
    with {:ok, source} <- find_in_play(state, player_id, instance_id),
         {:ok, player} <- fetch_player(state, player_id) do
      returned_cards = reset_tree_for_hand(source)

      player =
        player
        |> remove_in_play(instance_id)
        |> Map.update!(:hand, &(returned_cards ++ &1))

      {:ok, put_player(state, player)}
    end
  end

  defp damage_pokemon(state, player_id, instance_id, damage) do
    with {:ok, target} <- find_in_play(state, player_id, instance_id),
         {:ok, player} <- fetch_player(state, player_id) do
      damaged = %{target | damage: target.damage + damage}
      {:ok, put_player(state, replace_in_play(player, damaged))}
    end
  end

  defp heal_pokemon_damage(state, player_id, instance_id, damage) do
    with {:ok, target} <- find_in_play(state, player_id, instance_id),
         {:ok, player} <- fetch_player(state, player_id) do
      healed = %{target | damage: max(target.damage - damage, 0)}
      {:ok, put_player(state, replace_in_play(player, healed))}
    end
  end

  defp heal_all_pokemon_damage(state, player_id, instance_id) do
    with {:ok, target} <- find_in_play(state, player_id, instance_id),
         {:ok, player} <- fetch_player(state, player_id) do
      healed = %{target | damage: 0}
      {:ok, put_player(state, replace_in_play(player, healed))}
    end
  end

  defp return_attached_energy_to_hand(state, player_id, target_id) do
    with {:ok, target} <- find_in_play(state, player_id, target_id),
         {:ok, player} <- fetch_player(state, player_id),
         {:ok, returned_energy} <- attached_energy_to_hand_cards(target.attachments) do
      returned_energy_ids = MapSet.new(returned_energy, & &1.instance_id)

      updated_target = %{
        target
        | attachments:
            Enum.reject(target.attachments, &MapSet.member?(returned_energy_ids, &1.instance_id))
      }

      player =
        player
        |> replace_in_play(updated_target)
        |> Map.update!(:hand, &(returned_energy ++ &1))

      {:ok, put_player(state, player)}
    end
  end

  defp attached_energy_to_hand_cards(attachments) do
    attachments
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, returned_energy} ->
      with {:ok, true} <- energy_card?(attachment),
           {:ok, :hand} <- ZoneMovement.transition(:attached, :hand),
           {:ok, :in_hand} <- CardLifecycle.transition(attachment.lifecycle, :return_to_hand) do
        returned = %{attachment | zone: :hand, lifecycle: :in_hand}
        {:cont, {:ok, [returned | returned_energy]}}
      else
        {:ok, false} -> {:cont, {:ok, returned_energy}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, returned_energy} -> {:ok, Enum.reverse(returned_energy)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp energy_card?(%{card_id: card_id}) do
    with {:ok, metadata} <- Metadata.fetch(card_id) do
      {:ok, metadata.category == :energy}
    end
  end

  defp move_damage_counters(state, from_player_id, from_id, target_player_id, target_id, counters) do
    damage = counters * 10

    with {:ok, target} <- find_in_play(state, target_player_id, target_id),
         {:ok, state, :continue} <-
           maybe_prevent_damage_counter_move(
             state,
             from_player_id,
             target_player_id,
             target_id,
             target.zone,
             damage
           ),
         {:ok, state} <- heal_pokemon_damage(state, from_player_id, from_id, damage) do
      damage_pokemon(state, target_player_id, target_id, damage)
    else
      {:ok, state, :prevented} -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_prevent_damage_counter_move(
         state,
         source_player_id,
         target_player_id,
         target_id,
         target_zone,
         damage
       ) do
    context = %{
      source: :ability_effect,
      source_player_id: source_player_id,
      target_player_id: target_player_id,
      target_id: target_id,
      target_zone: target_zone,
      damage: damage,
      damage_kind: :damage_counters
    }

    case Hooks.run(state, :before_damage, context) do
      {:ok, state} ->
        {:ok, state, :continue}

      {:halt, {:damage_prevented_by_ability, _card_id, _ability_id}} ->
        {:ok, state, :prevented}

      {:halt, {:damage_prevented_by_attack_effect, _card_id, _attack_id}} ->
        {:ok, state, :prevented}

      {:halt, {:damage_prevented_by_stadium, _card_id, _effect_id}} ->
        {:ok, state, :prevented}

      {:halt, {:damage_prevented_by_energy, _card_id, _effect_id}} ->
        {:ok, state, :prevented}

      {:halt, reason} ->
        {:error, reason}
    end
  end

  defp set_pokemon_status(%{stadium: %{card_id: "TWM-149"}} = state, player_id, target, status) do
    if energy_attached?(target) do
      {:ok, state}
    else
      set_pokemon_status_without_immunity(state, player_id, target, status)
    end
  end

  defp set_pokemon_status(state, player_id, target, status) do
    set_pokemon_status_without_immunity(state, player_id, target, status)
  end

  defp set_pokemon_status_without_immunity(state, player_id, target, status) do
    with {:ok, player} <- fetch_player(state, player_id) do
      {:ok, put_player(state, replace_in_play(player, %{target | status: status}))}
    end
  end

  defp recover_special_conditions_from_festival_grounds(%{stadium: %{card_id: "TWM-149"}} = state) do
    players =
      Map.new(state.players, fn {player_id, player} ->
        player = %{
          player
          | active: recover_special_conditions_if_energy_attached(player.active),
            bench: Enum.map(player.bench, &recover_special_conditions_if_energy_attached/1)
        }

        {player_id, player}
      end)

    %{state | players: players}
  end

  defp recover_special_conditions_from_festival_grounds(state), do: state

  defp recover_special_condition_if_festival_grounds_active(pokemon, %{
         stadium: %{card_id: "TWM-149"}
       }) do
    recover_special_conditions_if_energy_attached(pokemon)
  end

  defp recover_special_condition_if_festival_grounds_active(pokemon, _state), do: pokemon

  defp recover_special_conditions_if_energy_attached(nil), do: nil

  defp recover_special_conditions_if_energy_attached(pokemon) do
    if energy_attached?(pokemon), do: %{pokemon | status: nil}, else: pokemon
  end

  defp energy_attached?(pokemon), do: attached_energy_count(pokemon) > 0

  defp resolve_knock_outs_after_damage(state, attacking_player_id, defending_player_id, target_id) do
    with {:ok, target} <- find_in_play(state, defending_player_id, target_id),
         {:ok, metadata} <- CardRegistry.fetch(target.card_id) do
      if target.damage >= Map.fetch!(metadata, :hp) do
        state
        |> knock_out_pokemon(defending_player_id, target)
        |> mark_knock_out_for_previous_turn_effects(
          attacking_player_id,
          defending_player_id,
          target
        )
        |> award_prizes(
          attacking_player_id,
          defending_player_id,
          Map.get(metadata, :prize_count, 1)
        )
        |> resolve_post_knock_out_game_state(attacking_player_id, defending_player_id)
      else
        {:ok, state}
      end
    end
  end

  defp knock_out_pokemon(state, player_id, target) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, :discard} <- ZoneMovement.transition(target.zone, :discard),
         {:ok, :discarded} <- CardLifecycle.transition(target.lifecycle, :knock_out) do
      discarded_cards = discard_tree(target)

      player =
        cond do
          player.active && player.active.instance_id == target.instance_id ->
            %{player | active: nil, discard: discarded_cards ++ player.discard}

          Enum.any?(player.bench, &(&1.instance_id == target.instance_id)) ->
            %{
              player
              | bench: reject_instance(player.bench, target.instance_id),
                discard: discarded_cards ++ player.discard
            }
        end

      {:ok, put_player(state, player)}
    end
  end

  defp mark_knock_out_for_previous_turn_effects(
         {:error, reason},
         _attacking_player_id,
         _defending_player_id,
         _target
       ),
       do: {:error, reason}

  defp mark_knock_out_for_previous_turn_effects(
         {:ok, state},
         same_player_id,
         same_player_id,
         _target
       ), do: {:ok, state}

  defp mark_knock_out_for_previous_turn_effects(
         {:ok, state},
         attacking_player_id,
         defending_player_id,
         target
       ) do
    if state.active_player == attacking_player_id do
      defending_player = state.players[defending_player_id]

      defending_player = %{
        defending_player
        | pokemon_knocked_out_during_opponents_last_turn?: true,
          team_rocket_pokemon_knocked_out_during_opponents_last_turn?:
            defending_player.team_rocket_pokemon_knocked_out_during_opponents_last_turn? ||
              team_rocket_pokemon?(target)
      }

      {:ok, put_player(state, defending_player)}
    else
      {:ok, state}
    end
  end

  defp discard_tree(nil), do: []

  defp discard_tree(card) do
    discarded = %{
      card
      | zone: :discard,
        lifecycle: :discarded,
        damage: 0,
        tool: nil,
        attachments: [],
        evolved_from: []
    }

    [discarded]
    |> Kernel.++(Enum.flat_map(card.attachments, &discard_tree/1))
    |> Kernel.++(discard_tree(card.tool))
    |> Kernel.++(Enum.flat_map(card.evolved_from, &discard_tree/1))
  end

  defp award_prizes({:ok, state}, player_id, defending_player_id, count),
    do: award_prizes(state, player_id, defending_player_id, count)

  defp award_prizes({:error, reason}, _player_id, _defending_player_id, _count),
    do: {:error, reason}

  defp award_prizes(state, _player_id, _defending_player_id, 0), do: {:ok, state}

  defp award_prizes(
         %{game_lifecycle: :choosing_prizes} = state,
         player_id,
         _defending_player_id,
         count
       )
       when count > 0 do
    with {:ok, pending_prizes} <- fetch_pending_prizes(state, player_id) do
      {:ok,
       %{
         state
         | pending_prizes: %{pending_prizes | remaining: pending_prizes.remaining + count}
       }}
    end
  end

  defp award_prizes(state, player_id, defending_player_id, count) when count > 0 do
    with {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :choose_prizes) do
      {:ok,
       %{
         state
         | game_lifecycle: game_lifecycle,
           pending_prizes: %{
             player_id: player_id,
             defending_player_id: defending_player_id,
             remaining: count
           }
       }}
    end
  end

  defp take_prize(state, player_id, instance_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      with {:ok, card} <- find_in_player_zone(state, player_id, :prizes, instance_id),
           {:ok, :hand} <- ZoneMovement.transition(:prizes, :hand),
           {:ok, :in_hand} <- CardLifecycle.transition(card.lifecycle, :take_prize) do
        card = %{card | zone: :hand, lifecycle: :in_hand}
        prizes = reject_instance(player.prizes, instance_id)
        player = %{player | prizes: prizes, hand: [card | player.hand]}
        state = put_player(state, player)

        if prizes == [] do
          {:ok, %{state | winner: player_id, game_lifecycle: :finished}}
        else
          {:ok, state}
        end
      end
    end
  end

  defp resolve_post_knock_out_game_state(
         {:error, reason},
         _attacking_player_id,
         _defending_player_id
       ),
       do: {:error, reason}

  defp resolve_post_knock_out_game_state(
         {:ok, %{winner: winner} = state},
         _attacking_player_id,
         _defending_player_id
       )
       when not is_nil(winner), do: {:ok, state}

  defp resolve_post_knock_out_game_state(
         {:ok, %{game_lifecycle: :choosing_prizes} = state},
         _attacking_player_id,
         _defending_player_id
       ),
       do: {:ok, state}

  defp resolve_post_knock_out_game_state({:ok, state}, attacking_player_id, defending_player_id) do
    with {:ok, defending_player} <- fetch_player(state, defending_player_id) do
      cond do
        defending_player.active ->
          finish_prize_resolution(state)

        defending_player.bench == [] ->
          {:ok, %{state | winner: attacking_player_id, game_lifecycle: :finished}}

        true ->
          with {:ok, game_lifecycle} <-
                 GameLifecycle.transition(state.game_lifecycle, :replace_active) do
            {:ok, %{state | game_lifecycle: game_lifecycle}}
          end
      end
    end
  end

  defp finish_prize_resolution(%{game_lifecycle: :resolving_attack} = state) do
    with {:ok, game_lifecycle} <- GameLifecycle.transition(:resolving_attack, :choose_prizes),
         {:ok, game_lifecycle} <- GameLifecycle.transition(game_lifecycle, :finish_prizes) do
      {:ok, %{state | game_lifecycle: game_lifecycle}}
    end
  end

  defp finish_prize_resolution(state), do: {:ok, state}

  defp finish_prize_resolution_after_choices(state, attacking_player_id, defending_player_id) do
    with {:ok, defending_player} <- fetch_player(state, defending_player_id) do
      cond do
        defending_player.active ->
          with {:ok, game_lifecycle} <-
                 GameLifecycle.transition(state.game_lifecycle, :finish_prizes) do
            {:ok, %{state | game_lifecycle: game_lifecycle}}
          end

        defending_player.bench == [] ->
          with {:ok, game_lifecycle} <- GameLifecycle.transition(state.game_lifecycle, :finish) do
            {:ok, %{state | winner: attacking_player_id, game_lifecycle: game_lifecycle}}
          end

        true ->
          with {:ok, game_lifecycle} <-
                 GameLifecycle.transition(state.game_lifecycle, :replace_active) do
            {:ok, %{state | game_lifecycle: game_lifecycle}}
          end
      end
    end
  end

  defp replace_in_play(player, card) do
    cond do
      player.active && player.active.instance_id == card.instance_id ->
        %{player | active: card}

      Enum.any?(player.bench, &(&1.instance_id == card.instance_id)) ->
        %{
          player
          | bench:
              Enum.map(player.bench, fn bench_card ->
                if bench_card.instance_id == card.instance_id, do: card, else: bench_card
              end)
        }

      true ->
        player
    end
  end

  defp replace_in_play(player, old_card, new_card) do
    cond do
      player.active && player.active.instance_id == old_card.instance_id ->
        %{player | active: new_card}

      Enum.any?(player.bench, &(&1.instance_id == old_card.instance_id)) ->
        %{
          player
          | bench:
              Enum.map(player.bench, fn bench_card ->
                if bench_card.instance_id == old_card.instance_id, do: new_card, else: bench_card
              end)
        }

      true ->
        player
    end
  end

  defp reset_turn_flags(player) do
    %{
      player
      | supporter_played?: false,
        energy_attached?: false,
        retreated?: false,
        markers: MapSet.new()
    }
  end

  defp fetch_pending_attack(
         %{pending_attack: %{player_id: player_id} = pending_attack},
         player_id
       ),
       do: {:ok, pending_attack}

  defp fetch_pending_attack(%{pending_attack: nil}, _player_id), do: {:error, :no_pending_attack}

  defp fetch_pending_attack(%{pending_attack: pending_attack}, player_id),
    do: {:error, {:pending_attack_belongs_to_other_player, pending_attack.player_id, player_id}}

  defp resolve_confusion_check(
         state,
         %{attacker_status: :confused, params: %{confusion_result: :tails}} = pending_attack
       ) do
    with {:ok, opponent_id} <- opponent_id(state, pending_attack.player_id),
         {:ok, state} <-
           damage_pokemon(state, pending_attack.player_id, pending_attack.attacker_id, 30),
         {:ok, state} <-
           resolve_knock_outs_after_damage(
             state,
             opponent_id,
             pending_attack.player_id,
             pending_attack.attacker_id
           ) do
      {:confused_tails, state}
    end
  end

  defp resolve_confusion_check(state, %{
         attacker_status: :confused,
         params: %{confusion_result: :heads}
       }),
       do: {:ok, state}

  defp resolve_confusion_check(state, _pending_attack), do: {:ok, state}

  defp attack_damage(state, pending_attack) do
    base_damage = base_attack_damage(state, pending_attack)

    with {:ok, modified_damage} <- modify_attack_damage(state, pending_attack, base_damage) do
      {:ok, apply_weakness_and_resistance(modified_damage, state, pending_attack)}
    end
  end

  defp damage_active_pokemon_from_attack(state, pending_attack, damage) do
    context = %{
      source: :attack,
      attack: pending_attack.attack,
      attacking_player_id: pending_attack.player_id,
      attacker_id: pending_attack.attacker_id,
      target_player_id: pending_attack.target_player_id,
      target_id: pending_attack.target_id,
      target_zone: :active,
      damage: damage,
      damage_kind: :damage,
      params: pending_attack.params
    }

    case Hooks.run(state, :before_damage, context) do
      {:ok, state} ->
        with {:ok, state} <-
               damage_pokemon(
                 state,
                 pending_attack.target_player_id,
                 pending_attack.target_id,
                 damage
               ) do
          {:ok, state, :damage_applied}
        end

      {:halt, {:damage_prevented_by_ability, _card_id, _ability_id}} ->
        {:ok, state, :damage_prevented}

      {:halt, {:damage_prevented_by_attack_effect, _card_id, _attack_id}} ->
        {:ok, state, :damage_prevented}

      {:halt, {:damage_prevented_by_stadium, _card_id, _effect_id}} ->
        {:ok, state, :damage_prevented}

      {:halt, {:damage_prevented_by_energy, _card_id, _effect_id}} ->
        {:ok, state, :damage_prevented}

      {:halt, reason} ->
        {:error, reason}
    end
  end

  defp maybe_run_after_attack_damage_hooks(state, _pending_attack, _damage, :damage_prevented),
    do: {:ok, state}

  defp maybe_run_after_attack_damage_hooks(state, pending_attack, damage, :damage_applied),
    do: run_after_attack_damage_hooks(state, pending_attack, damage)

  defp maybe_resolve_knock_outs_after_attack_damage(state, _pending_attack, :damage_prevented),
    do: {:ok, state}

  defp maybe_resolve_knock_outs_after_attack_damage(state, pending_attack, :damage_applied) do
    resolve_knock_outs_after_damage(
      state,
      pending_attack.player_id,
      pending_attack.target_player_id,
      pending_attack.target_id
    )
  end

  defp modify_attack_damage(
         state,
         %{
           attack: attack,
           player_id: player_id,
           attacker_id: attacker_id,
           target_player_id: target_player_id,
           target_id: target_id,
           params: params
         },
         damage
       ) do
    context = %{
      source: :attack,
      attack: attack,
      attacking_player_id: player_id,
      attacker_id: attacker_id,
      target_player_id: target_player_id,
      target_id: target_id,
      target_zone: :active,
      damage: damage,
      params: params
    }

    case Hooks.run(state, :modify_damage, context) do
      {:ok, modified_damage} when is_integer(modified_damage) and modified_damage >= 0 ->
        {:ok, modified_damage}

      {:ok, modified_damage} ->
        {:error, {:invalid_modified_damage, modified_damage}}

      {:halt, reason} ->
        {:error, reason}
    end
  end

  defp base_attack_damage(state, %{
         attack: %{
           effect: %{type: :active_damage_counters_per_hand_card, counters_per_card: counters}
         },
         player_id: player_id
       }) do
    player = Map.fetch!(state.players, player_id)
    length(player.hand) * counters * 10
  end

  defp base_attack_damage(state, %{
         attack: %{damage: damage, effect: %{type: :bonus_damage_if_defender_pokemon_ex} = effect},
         target_player_id: target_player_id,
         target_id: target_id
       }) do
    with {:ok, target} <- find_in_play(state, target_player_id, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id) do
      if pokemon_ex?(target_metadata), do: damage + effect.bonus_damage, else: damage
    else
      {:error, _reason} -> damage
    end
  end

  defp base_attack_damage(state, %{
         attack: %{
           damage: damage,
           effect: %{type: :bonus_damage_per_energy_attached_to_defender} = effect
         },
         target_player_id: target_player_id,
         target_id: target_id
       }) do
    case find_in_play(state, target_player_id, target_id) do
      {:ok, target} -> damage + attached_energy_count(target) * Map.fetch!(effect, :bonus_damage)
      {:error, _reason} -> damage
    end
  end

  defp base_attack_damage(state, %{
         attack: %{
           effect: %{
             type: :damage_per_own_basic_pokemon_in_play,
             damage_per_pokemon: damage_per_pokemon
           }
         },
         player_id: player_id
       }) do
    basic_pokemon_in_play_count(state, player_id) * damage_per_pokemon
  end

  defp base_attack_damage(state, %{
         attack: %{
           effect: %{
             type: :damage_per_own_team_rocket_pokemon_in_play,
             damage_per_pokemon: damage_per_pokemon
           }
         },
         player_id: player_id
       }) do
    team_rocket_pokemon_in_play_count(state, player_id) * damage_per_pokemon
  end

  defp base_attack_damage(_state, %{
         attack: %{
           damage: damage,
           effect: %{type: :bonus_damage_on_coin_heads, bonus_damage: bonus_damage}
         },
         params: %{coin_result: :heads}
       }) do
    damage + bonus_damage
  end

  defp base_attack_damage(_state, %{
         attack: %{damage: damage, effect: %{type: :bonus_damage_on_coin_heads}},
         params: %{coin_result: :tails}
       }) do
    damage
  end

  defp base_attack_damage(_state, %{
         attack: %{
           damage: damage,
           effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: bonus_damage}
         },
         params: %{heads_count: heads_count}
       }) do
    damage + heads_count * bonus_damage
  end

  defp base_attack_damage(state, %{
         attack: %{
           damage: damage,
           effect: %{
             type: :bonus_damage_if_moved_from_bench_to_active_this_turn,
             bonus_damage: bonus_damage
           }
         },
         player_id: player_id,
         attacker_id: attacker_id
       }) do
    if moved_from_bench_to_active_this_turn?(state, player_id, attacker_id) do
      damage + bonus_damage
    else
      damage
    end
  end

  defp base_attack_damage(%{stadium: nil}, %{
         attack: %{effect: %{type: :damage_only_if_stadium_in_play}}
       }) do
    0
  end

  defp base_attack_damage(_state, %{
         attack: %{damage: damage, effect: %{type: :damage_only_if_stadium_in_play}}
       }) do
    damage
  end

  defp base_attack_damage(_state, %{attack: attack}), do: Map.fetch!(attack, :damage)

  defp basic_pokemon_in_play_count(state, player_id) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        player
        |> in_play_pokemon()
        |> Enum.count(fn pokemon ->
          match?(
            {:ok, %{supertype: :pokemon, stage: :basic}},
            CardRegistry.fetch(pokemon.card_id)
          )
        end)

      {:error, _reason} ->
        0
    end
  end

  defp team_rocket_pokemon_in_play_count(state, player_id) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        player
        |> in_play_pokemon()
        |> Enum.count(fn pokemon ->
          match?(
            {:ok, %{supertype: :pokemon, name: "Team Rocket's " <> _}},
            CardRegistry.fetch(pokemon.card_id)
          )
        end)

      {:error, _reason} ->
        0
    end
  end

  defp all_own_pokemon_in_play_are_team_rocket?(state, player_id) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        pokemon = in_play_pokemon(player)
        pokemon != [] && Enum.all?(pokemon, &team_rocket_pokemon?/1)

      {:error, _reason} ->
        false
    end
  end

  defp team_rocket_pokemon?(pokemon) do
    match?(
      {:ok, %Metadata{category: :pokemon, name: "Team Rocket's " <> _name}},
      Metadata.fetch(pokemon.card_id)
    )
  end

  defp moved_from_bench_to_active_this_turn?(state, player_id, pokemon_id) do
    case fetch_player(state, player_id) do
      {:ok, player} ->
        MapSet.member?(player.markers, {:moved_from_bench_to_active_this_turn, pokemon_id})

      {:error, _reason} ->
        false
    end
  end

  defp require_team_rocket_pokemon_for_giovanni(pokemon, position) do
    if team_rocket_pokemon?(pokemon) do
      :ok
    else
      {:error, {:team_rockets_giovanni_requires_team_rocket_pokemon, position, pokemon.card_id}}
    end
  end

  defp in_play_pokemon(player) do
    Enum.reject([player.active | player.bench], &is_nil/1)
  end

  defp attached_energy_count(pokemon) do
    Enum.count(pokemon.attachments, fn attachment ->
      match?({:ok, %{supertype: :energy}}, CardRegistry.fetch(attachment.card_id))
    end)
  end

  defp apply_weakness_and_resistance(0, _state, _pending_attack), do: 0

  defp apply_weakness_and_resistance(damage, state, %{
         player_id: player_id,
         target_player_id: target_player_id,
         target_id: target_id
       }) do
    with {:ok, attacker} <- fetch_player(state, player_id),
         %{active: active_attacker} when not is_nil(active_attacker) <- attacker,
         {:ok, attacker_metadata} <- CardRegistry.fetch(active_attacker.card_id),
         {:ok, target} <- find_in_play(state, target_player_id, target_id),
         true <- active_target?(state, target_player_id, target),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id) do
      damage
      |> apply_weakness(attacker_metadata[:type], target_metadata[:weakness])
      |> apply_resistance(attacker_metadata[:type], target_metadata[:resistance])
    else
      _ -> damage
    end
  end

  defp active_target?(state, player_id, target) do
    case fetch_player(state, player_id) do
      {:ok, %{active: %{instance_id: instance_id}}} -> instance_id == target.instance_id
      _ -> false
    end
  end

  defp bench_target?(state, player_id, target_id) do
    match?({:ok, _target}, find_in_player_zone(state, player_id, :bench, target_id))
  end

  defp apply_weakness(damage, type, %{type: type, multiplier: multiplier}),
    do: damage * multiplier

  defp apply_weakness(damage, _type, _weakness), do: damage

  defp apply_resistance(damage, type, %{type: type, value: value}), do: max(damage + value, 0)
  defp apply_resistance(damage, _type, _resistance), do: damage

  defp pokemon_ex?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex")
  end

  defp pokemon_ex?(_metadata), do: false

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :switch_self_with_bench}},
         player_id: player_id,
         params: %{switch_id: switch_id}
       }) do
    with {:ok, target} <- find_in_player_zone(state, player_id, :bench, switch_id) do
      switch_own_bench_to_active(state, player_id, target, retreated?: false)
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :opponent_bench_damage_counters}},
         player_id: player_id,
         target_player_id: target_player_id,
         params: %{bench_damage: bench_damage}
       }) do
    Enum.reduce_while(bench_damage, {:ok, state}, fn {target_id, counters}, {:ok, state} ->
      result =
        damage_bench_pokemon_from_attack_effect(
          state,
          player_id,
          target_player_id,
          target_id,
          counters * 10,
          :damage_counters
        )

      case result do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :self_damage, damage: damage}},
         player_id: player_id,
         attacker_id: attacker_id
       }) do
    with {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, state} <- damage_pokemon(state, player_id, attacker_id, damage) do
      resolve_knock_outs_after_damage(state, opponent_id, player_id, attacker_id)
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :lock_opponent_items_next_turn}},
         target_player_id: target_player_id
       }) do
    with {:ok, target_player} <- fetch_player(state, target_player_id) do
      {:ok, put_player(state, %{target_player | item_cards_locked?: true})}
    end
  end

  defp resolve_attack_effect(
         state,
         %{
           attack: %{effect: %{type: :confuse_defender_active}},
           target_player_id: target_player_id,
           target_id: target_id
         } =
           pending_attack
       ) do
    case attack_effect_prevention_result(
           state,
           pending_attack,
           target_player_id,
           target_id,
           :active
         ) do
      {:ok, state, :continue} ->
        case find_in_play(state, target_player_id, target_id) do
          {:ok, target} -> set_pokemon_status(state, target_player_id, target, :confused)
          {:error, _reason} -> {:ok, state}
        end

      {:ok, state, :prevented} ->
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{
           effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}
         },
         player_id: player_id,
         attacker_id: attacker_id,
         params: %{coin_result: :heads}
       }) do
    put_player_marker(
      state,
      player_id,
      {:prevent_damage_and_effects_from_attacks, attacker_id, :dig}
    )
  end

  defp resolve_attack_effect(state, %{
         attack: %{
           effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}
         },
         params: %{coin_result: :tails}
       }),
       do: {:ok, state}

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :damage_one_opponent_pokemon, damage: damage}},
         player_id: player_id,
         target_player_id: target_player_id,
         params: %{target_id: target_id}
       }) do
    target_zone = if bench_target?(state, target_player_id, target_id), do: :bench, else: :active

    damage_pokemon_from_attack_effect(
      state,
      player_id,
      target_player_id,
      target_id,
      target_zone,
      damage,
      :damage
    )
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :recover_trainer_from_discard_to_hand}},
         player_id: player_id,
         params: %{target_id: target_id}
       }) do
    with {:ok, target} <- find_in_player_zone(state, player_id, :discard, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_trainer(target_metadata) do
      move_discard_card_to_hand(state, player_id, target)
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :search_pokemon_to_hand}},
         player_id: player_id,
         params: %{target_id: target_id}
       }) do
    with {:ok, target} <- find_in_player_zone(state, player_id, :deck, target_id),
         {:ok, target_metadata} <- CardRegistry.fetch(target.card_id),
         :ok <- require_pokemon(target_metadata) do
      move_deck_card_to_hand(state, player_id, target)
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :discard_hand_then_draw, count: count}},
         player_id: player_id
       }) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, state} <- discard_hand_cards(state, player_id, player.hand) do
      draw_cards(state, player_id, count)
    end
  end

  defp resolve_attack_effect(state, %{
         attack: %{effect: %{type: :return_attacker_and_attached_to_hand}},
         player_id: player_id,
         attacker_id: attacker_id
       }) do
    return_in_play_tree_to_hand(state, player_id, attacker_id)
  end

  defp resolve_attack_effect(state, _pending_attack), do: {:ok, state}

  defp run_after_attack_damage_hooks(state, pending_attack, damage) do
    context = %{
      source: :attack,
      attack: pending_attack.attack,
      attacking_player_id: pending_attack.player_id,
      attacker_id: pending_attack.attacker_id,
      target_player_id: pending_attack.target_player_id,
      target_id: pending_attack.target_id,
      target_zone: :active,
      damage: damage,
      params: pending_attack.params
    }

    case Hooks.run(state, :after_damage, context) do
      {:ok, state} -> {:ok, state}
      {:halt, reason} -> {:error, reason}
    end
  end

  defp damage_bench_pokemon_from_attack_effect(
         state,
         attacking_player_id,
         target_player_id,
         target_id,
         damage,
         damage_kind
       ) do
    damage_pokemon_from_attack_effect(
      state,
      attacking_player_id,
      target_player_id,
      target_id,
      :bench,
      damage,
      damage_kind
    )
  end

  defp damage_pokemon_from_attack_effect(
         state,
         attacking_player_id,
         target_player_id,
         target_id,
         target_zone,
         damage,
         damage_kind
       ) do
    context = %{
      source: :attack_effect,
      attacking_player_id: attacking_player_id,
      target_player_id: target_player_id,
      target_id: target_id,
      target_zone: target_zone,
      damage: damage,
      damage_kind: damage_kind
    }

    case Hooks.run(state, :before_damage, context) do
      {:ok, state} ->
        with {:ok, state} <- damage_pokemon(state, target_player_id, target_id, damage) do
          resolve_knock_outs_after_damage(state, attacking_player_id, target_player_id, target_id)
        end

      {:halt, {:damage_prevented_by_ability, _card_id, _ability_id}} ->
        {:ok, state}

      {:halt, {:damage_prevented_by_attack_effect, _card_id, _attack_id}} ->
        {:ok, state}

      {:halt, {:damage_prevented_by_stadium, _card_id, _effect_id}} ->
        {:ok, state}

      {:halt, {:damage_prevented_by_energy, _card_id, _effect_id}} ->
        {:ok, state}

      {:halt, reason} ->
        {:error, reason}
    end
  end

  defp attack_effect_prevention_result(
         state,
         pending_attack,
         target_player_id,
         target_id,
         target_zone
       ) do
    context = %{
      source: :attack_effect,
      attack: pending_attack.attack,
      attacking_player_id: pending_attack.player_id,
      attacker_id: pending_attack.attacker_id,
      target_player_id: target_player_id,
      target_id: target_id,
      target_zone: target_zone,
      effect_kind: :effect,
      params: pending_attack.params
    }

    case Hooks.run(state, :before_attack_effect, context) do
      {:ok, state} ->
        {:ok, state, :continue}

      {:halt, {:attack_effect_prevented_by_attack_effect, _card_id, _attack_id}} ->
        {:ok, state, :prevented}

      {:halt, {:attack_effect_prevented_by_energy, _card_id, _effect_id}} ->
        {:ok, state, :prevented}

      {:halt, reason} ->
        {:error, reason}
    end
  end

  defp damp_active?(state) do
    state.players
    |> Map.values()
    |> Enum.flat_map(&in_play_cards/1)
    |> Enum.any?(&(&1.card_id == "ASC-039"))
  end

  defp in_play_cards(player), do: Enum.reject([player.active | player.bench], &is_nil/1)

  defp require_attack_effect_params(
         %{effect: %{type: :switch_self_with_bench}},
         params,
         _defender
       ) do
    if Map.has_key?(params, :switch_id),
      do: :ok,
      else: {:error, :missing_switch_target_for_attack}
  end

  defp require_attack_effect_params(
         %{effect: %{type: :opponent_bench_damage_counters, total_counters: total_counters}},
         params,
         defender
       ) do
    bench_damage = Map.get(params, :bench_damage, %{})

    cond do
      not is_map(bench_damage) ->
        {:error, :bench_damage_must_be_map}

      Enum.any?(bench_damage, fn {_target_id, counters} ->
        not is_integer(counters) or counters < 0
      end) ->
        {:error, :invalid_bench_damage_counters}

      Enum.sum(Map.values(bench_damage)) != total_counters ->
        {:error,
         {:wrong_bench_damage_counter_total, Enum.sum(Map.values(bench_damage)), total_counters}}

      Enum.any?(Map.keys(bench_damage), fn target_id ->
        not Enum.any?(defender.bench, &(&1.instance_id == target_id))
      end) ->
        {:error, :bench_damage_target_not_found}

      true ->
        :ok
    end
  end

  defp require_attack_effect_params(
         %{effect: %{type: :damage_one_opponent_pokemon}},
         params,
         defender
       ) do
    target_id = Map.get(params, :target_id)

    cond do
      is_nil(target_id) ->
        {:error, :missing_damage_target_for_attack}

      defender.active && defender.active.instance_id == target_id ->
        :ok

      Enum.any?(defender.bench, &(&1.instance_id == target_id)) ->
        :ok

      true ->
        {:error, :damage_target_not_found}
    end
  end

  defp require_attack_effect_params(
         %{effect: %{type: :recover_trainer_from_discard_to_hand}},
         params,
         _defender
       ) do
    if Map.has_key?(params, :target_id),
      do: :ok,
      else: {:error, :missing_discard_trainer_target_for_attack}
  end

  defp require_attack_effect_params(
         %{effect: %{type: :search_pokemon_to_hand}},
         params,
         _defender
       ) do
    case Map.fetch(params, :target_id) do
      {:ok, target_id} when not is_nil(target_id) -> :ok
      _missing_or_nil -> {:error, :missing_deck_pokemon_target_for_attack}
    end
  end

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_on_coin_heads}},
         %{coin_result: result},
         _defender
       )
       when result in [:heads, :tails], do: :ok

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_on_coin_heads}},
         %{coin_result: result},
         _defender
       ),
       do: {:error, {:invalid_coin_result, result}}

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_on_coin_heads}},
         _params,
         _defender
       ),
       do: {:error, :missing_coin_result}

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_per_coin_heads_count}},
         %{heads_count: heads_count},
         _defender
       )
       when is_integer(heads_count) and heads_count >= 0, do: :ok

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_per_coin_heads_count}},
         %{heads_count: heads_count},
         _defender
       ),
       do: {:error, {:invalid_heads_count, heads_count}}

  defp require_attack_effect_params(
         %{effect: %{type: :bonus_damage_per_coin_heads_count}},
         _params,
         _defender
       ),
       do: {:error, :missing_heads_count}

  defp require_attack_effect_params(
         %{effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}},
         %{coin_result: result},
         _defender
       )
       when result in [:heads, :tails], do: :ok

  defp require_attack_effect_params(
         %{effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}},
         %{coin_result: result},
         _defender
       ),
       do: {:error, {:invalid_coin_result, result}}

  defp require_attack_effect_params(
         %{effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}},
         _params,
         _defender
       ),
       do: {:error, :missing_coin_result}

  defp require_attack_effect_params(_attack, _params, _defender), do: :ok

  defp require_attack_cost(state, player_id, attacker, attack) do
    provided_types =
      Enum.flat_map(attacker.attachments, fn attachment ->
        attachment.card_id
        |> CardRegistry.fetch!()
        |> Map.get(:provides, [])
      end)

    with {:ok, cost} <- effective_attack_cost(state, player_id, attacker, attack.cost) do
      if can_pay_cost?(cost, provided_types) do
        :ok
      else
        {:error, {:cannot_pay_attack_cost, attack.id, cost, provided_types}}
      end
    end
  end

  defp effective_attack_cost(state, player_id, attacker, cost) do
    with {:ok, player} <- fetch_player(state, player_id),
         {:ok, opponent_id} <- opponent_id(state, player_id),
         {:ok, opponent} <- fetch_player(state, opponent_id) do
      cost =
        if counter_gain_active?(player, opponent, attacker) do
          drop_colorless_cost(cost, 1)
        else
          cost
        end

      {:ok, cost}
    end
  end

  defp counter_gain_active?(player, opponent, %{tool: %{card_id: "SSP-169"}}) do
    length(player.prizes) > length(opponent.prizes)
  end

  defp counter_gain_active?(_player, _opponent, _attacker), do: false

  defp require_confusion_result(%{status: :confused}, %{confusion_result: result})
       when result in [:heads, :tails],
       do: :ok

  defp require_confusion_result(%{status: :confused}, %{confusion_result: result}),
    do: {:error, {:invalid_confusion_result, result}}

  defp require_confusion_result(%{status: :confused}, _params),
    do: {:error, :missing_confusion_result}

  defp require_confusion_result(_attacker, _params), do: :ok

  defp can_pay_cost?(cost, provided_types) do
    {typed_cost, colorless_cost} = Enum.split_with(cost, &(&1 != :colorless))

    case consume_typed_cost(typed_cost, provided_types) do
      {:ok, remaining_types} -> length(remaining_types) >= length(colorless_cost)
      :error -> false
    end
  end

  defp consume_typed_cost([], provided_types), do: {:ok, provided_types}

  defp consume_typed_cost([type | rest], provided_types) do
    if type in provided_types do
      consume_typed_cost(rest, remove_one_type(provided_types, type))
    else
      :error
    end
  end

  defp remove_one_type(types, type) do
    {before_match, [_match | after_match]} = Enum.split_while(types, &(&1 != type))
    before_match ++ after_match
  end

  defp finish_attack_game_lifecycle(:resolving_attack),
    do: GameLifecycle.transition(:resolving_attack, :finish_attack)

  defp finish_attack_game_lifecycle(:in_progress), do: {:ok, :in_progress}
  defp finish_attack_game_lifecycle(:finished), do: {:ok, :finished}

  defp finish_attack_game_lifecycle(other),
    do: {:error, {:cannot_finish_attack_from_game_lifecycle, other}}

  defp end_turn_lifecycle(:end_turn), do: TurnLifecycle.transition(:end_turn, :between_turns)

  defp end_turn_lifecycle(turn_lifecycle) do
    with {:ok, turn_lifecycle} <- TurnLifecycle.transition(turn_lifecycle, :end_turn) do
      TurnLifecycle.transition(turn_lifecycle, :between_turns)
    end
  end

  defp fetch_player(state, player_id) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} -> {:ok, player}
      :error -> {:error, {:unknown_player, player_id}}
    end
  end

  defp fetch_pending_prizes(
         %{pending_prizes: %{player_id: player_id} = pending_prizes},
         player_id
       ),
       do: {:ok, pending_prizes}

  defp fetch_pending_prizes(%{pending_prizes: nil}, _player_id), do: {:error, :no_pending_prizes}

  defp fetch_pending_prizes(%{pending_prizes: %{player_id: pending_player_id}}, player_id),
    do: {:error, {:not_pending_prize_player, player_id, pending_player_id}}

  defp put_player(state, player),
    do: %{state | players: Map.put(state.players, player.id, player)}

  defp put_player_marker(state, player_id, marker) do
    with {:ok, player} <- fetch_player(state, player_id) do
      {:ok, put_player(state, %{player | markers: MapSet.put(player.markers, marker)})}
    end
  end

  defp require_active_player(%{active_player: player_id}, player_id), do: :ok

  defp require_active_player(%{active_player: active_player}, player_id),
    do: {:error, {:not_active_player, player_id, active_player}}

  defp opponent_id(state, player_id) do
    state.players
    |> Map.keys()
    |> Enum.reject(&(&1 == player_id))
    |> case do
      [opponent_id] -> {:ok, opponent_id}
      opponents -> {:error, {:expected_one_opponent, opponents}}
    end
  end

  defp require_turn_lifecycle(%{turn_lifecycle: expected}, expected), do: :ok

  defp require_turn_lifecycle(%{turn_lifecycle: actual}, expected),
    do: {:error, {:wrong_turn_lifecycle, actual, expected}}

  defp require_game_lifecycle(%{game_lifecycle: expected}, expected), do: :ok

  defp require_game_lifecycle(%{game_lifecycle: actual}, expected),
    do: {:error, {:wrong_game_lifecycle, actual, expected}}

  defp require_not_finished(%{game_lifecycle: :finished}), do: {:error, :game_already_finished}
  defp require_not_finished(_state), do: :ok

  defp require_all_players_have_active(state) do
    state.players
    |> Enum.find(fn {_player_id, player} -> is_nil(player.active) end)
    |> case do
      nil -> :ok
      {player_id, _player} -> {:error, {:missing_active_pokemon, player_id}}
    end
  end

  defp require_no_player_has_prizes(state) do
    state.players
    |> Enum.find(fn {_player_id, player} -> player.prizes != [] end)
    |> case do
      nil -> :ok
      {player_id, _player} -> {:error, {:prizes_already_placed, player_id}}
    end
  end

  defp require_all_players_have_prizes(state, count) do
    state.players
    |> Enum.find(fn {_player_id, player} -> length(player.prizes) != count end)
    |> case do
      nil ->
        :ok

      {player_id, player} ->
        {:error, {:wrong_prize_count, player_id, length(player.prizes), count}}
    end
  end

  defp require_no_setup_pokemon_chosen(%{active: nil, bench: []}), do: :ok

  defp require_no_setup_pokemon_chosen(player),
    do: {:error, {:cannot_mulligan_after_setup_pokemon_chosen, player.id}}

  defp require_opening_hand_ready_for_mulligan(%{hand: hand}) when length(hand) == 7, do: :ok

  defp require_opening_hand_ready_for_mulligan(%{hand: hand}),
    do: {:error, {:mulligan_requires_seven_card_hand, length(hand)}}

  defp require_no_basic_pokemon_in_hand(player) do
    if Enum.any?(player.hand, &CardRegistry.basic_pokemon?(&1.card_id)) do
      {:error, :cannot_mulligan_with_basic_pokemon_in_hand}
    else
      :ok
    end
  end

  defp require_mulligan_bonus_available(_player, _opponent, 0), do: :ok

  defp require_mulligan_bonus_available(player, opponent, count) do
    available = opponent.mulligans_taken - player.mulligan_bonus_draws_taken

    if count <= available do
      :ok
    else
      {:error, {:too_many_mulligan_bonus_cards, count, available}}
    end
  end

  defp require_active_pokemon(player_id, %{active: nil}),
    do: {:error, {:missing_active_pokemon, player_id}}

  defp require_active_pokemon(_player_id, _player), do: :ok

  defp require_active_source(%{active: active}, player_id, instance_id) when not is_nil(active) do
    if active.instance_id == instance_id do
      {:ok, active}
    else
      {:error, {:pokemon_not_active, player_id, instance_id}}
    end
  end

  defp require_active_source(_player, player_id, instance_id),
    do: {:error, {:pokemon_not_active, player_id, instance_id}}

  defp require_can_attack(%{status: status}) when status in [:asleep, :paralyzed],
    do: {:error, {:cannot_attack_while, status}}

  defp require_can_attack(_pokemon), do: :ok

  defp require_can_retreat(%{status: status}) when status in [:asleep, :paralyzed],
    do: {:error, {:cannot_retreat_while, status}}

  defp require_can_retreat(_pokemon), do: :ok

  defp require_basic_pokemon(%{supertype: :pokemon, stage: :basic}), do: :ok
  defp require_basic_pokemon(metadata), do: {:error, {:not_basic_pokemon, metadata}}

  defp require_energy(%{supertype: :energy}), do: :ok
  defp require_energy(metadata), do: {:error, {:not_energy, metadata}}

  defp require_basic_energy(%{supertype: :energy, energy_type: :basic}), do: :ok
  defp require_basic_energy(metadata), do: {:error, {:not_basic_energy, metadata}}

  defp require_optional_basic_energy(nil), do: :ok
  defp require_optional_basic_energy(metadata), do: require_basic_energy(metadata)

  defp require_night_stretcher_target(%{supertype: :pokemon}), do: :ok
  defp require_night_stretcher_target(%{supertype: :energy, energy_type: :basic}), do: :ok

  defp require_night_stretcher_target(metadata),
    do: {:error, {:invalid_night_stretcher_target, metadata.id}}

  defp require_lanas_aid_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      result =
        with {:ok, metadata} <- CardRegistry.fetch(target.card_id) do
          case metadata do
            %{supertype: :pokemon} -> require_non_rule_box_pokemon(metadata)
            %{supertype: :energy, energy_type: :basic} -> :ok
            _ -> {:error, {:invalid_lanas_aid_target, metadata.id}}
          end
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_pokemon(%{supertype: :pokemon}), do: :ok
  defp require_pokemon(metadata), do: {:error, {:not_pokemon, metadata}}

  defp require_non_rule_box_pokemon(%{supertype: :pokemon} = metadata) do
    if Map.get(metadata, :rule_box?, false) do
      {:error, {:pokemon_has_rule_box, metadata.id}}
    else
      :ok
    end
  end

  defp require_non_rule_box_pokemon(metadata), do: {:error, {:not_pokemon, metadata}}

  defp require_pokemon_stage(card, stage) do
    case CardRegistry.fetch(card.card_id) do
      {:ok, %{supertype: :pokemon, stage: ^stage}} ->
        :ok

      {:ok, metadata} ->
        {:error, {:wrong_pokemon_stage, metadata.id, Map.get(metadata, :stage), stage}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_evolution_pokemon(card) do
    case CardRegistry.fetch(card.card_id) do
      {:ok, %{supertype: :pokemon, stage: stage} = metadata} ->
        if stage in [:stage_1, :stage_2] do
          :ok
        else
          {:error, {:not_evolution_pokemon, metadata.id, stage}}
        end

      {:ok, metadata} ->
        {:error, {:not_pokemon, metadata}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_all_pokemon(cards) do
    Enum.reduce_while(cards, :ok, fn card, :ok ->
      with {:ok, metadata} <- CardRegistry.fetch(card.card_id),
           :ok <- require_pokemon(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_stage_2(%{supertype: :pokemon, stage: :stage_2}), do: :ok
  defp require_stage_2(metadata), do: {:error, {:not_stage_2_pokemon, metadata}}

  defp require_trainer(%{supertype: :trainer}), do: :ok
  defp require_trainer(metadata), do: {:error, {:not_trainer, metadata}}

  defp require_supporter(%{supertype: :trainer, trainer_type: :supporter}), do: :ok
  defp require_supporter(metadata), do: {:error, {:not_supporter, metadata}}

  defp require_optional_supporter(nil), do: :ok
  defp require_optional_supporter(metadata), do: require_supporter(metadata)

  defp require_stadium(%{supertype: :trainer, trainer_type: :stadium}), do: :ok
  defp require_stadium(metadata), do: {:error, {:not_stadium, metadata}}

  defp require_tool(%{supertype: :trainer, trainer_type: :tool}), do: :ok
  defp require_tool(metadata), do: {:error, {:not_tool, metadata}}

  defp require_no_tool_attached(%{tool: nil}), do: :ok

  defp require_no_tool_attached(target),
    do: {:error, {:tool_already_attached, target.instance_id}}

  defp require_supporter_available_if_supporter(%{trainer_type: :supporter}, state, player_id) do
    with :ok <- require_first_player_can_play_supporter(state, player_id),
         {:ok, player} <- fetch_player(state, player_id) do
      if player.supporter_played? do
        {:error, :supporter_already_played_this_turn}
      else
        :ok
      end
    end
  end

  defp require_supporter_available_if_supporter(_metadata, _state, _player_id), do: :ok

  defp require_first_player_can_attack(%{first_player: player_id, turn_number: 1}, player_id),
    do: {:error, :first_player_cannot_attack_on_first_turn}

  defp require_first_player_can_attack(_state, _player_id), do: :ok

  defp require_first_player_can_play_supporter(
         %{first_player: player_id, turn_number: 1},
         player_id
       ),
       do: {:error, :first_player_cannot_play_supporter_on_first_turn}

  defp require_first_player_can_play_supporter(_state, _player_id), do: :ok

  defp require_player_first_turn(%{first_player: player_id, turn_number: 1}, player_id, _action),
    do: :ok

  defp require_player_first_turn(
         %{first_player: first_player, turn_number: 2},
         player_id,
         _action
       )
       when first_player != player_id, do: :ok

  defp require_player_first_turn(%{turn_number: turn_number}, player_id, action),
    do: {:error, {:not_players_first_turn, action, player_id, turn_number}}

  defp require_team_rockets_proton_supporter_available(
         %{trainer_type: :supporter},
         %{first_player: player_id, turn_number: 1} = state,
         player_id
       ) do
    with {:ok, player} <- fetch_player(state, player_id) do
      if player.supporter_played? do
        {:error, :supporter_already_played_this_turn}
      else
        :ok
      end
    end
  end

  defp require_team_rockets_proton_supporter_available(metadata, state, player_id),
    do: require_supporter_available_if_supporter(metadata, state, player_id)

  defp require_item_cards_playable_if_item(%{trainer_type: :item}, state, player_id) do
    require_item_cards_playable(state, player_id)
  end

  defp require_item_cards_playable_if_item(_metadata, _state, _player_id), do: :ok

  defp require_item_cards_playable(state, player_id) do
    state
    |> Hooks.run(:before_play_trainer, %{player_id: player_id, metadata: %{trainer_type: :item}})
    |> require_hook_success()
  end

  defp require_ace_spec_cards_playable_if_ace_spec(%{ace_spec?: true}, state, player_id) do
    require_ace_spec_cards_playable(state, player_id)
  end

  defp require_ace_spec_cards_playable_if_ace_spec(_metadata, _state, _player_id), do: :ok

  defp require_ace_spec_cards_playable(state, player_id) do
    state
    |> Hooks.run(:before_play_trainer, %{player_id: player_id, metadata: %{ace_spec?: true}})
    |> require_hook_success()
  end

  defp require_hook_success({:ok, _state}), do: :ok
  defp require_hook_success({:halt, reason}), do: {:error, reason}

  defp require_card_id(%{card_id: card_id}, card_id), do: :ok

  defp require_card_id(card, expected),
    do: {:error, {:wrong_card_for_action, expected, card.card_id}}

  defp require_different_in_play_targets(instance_id, instance_id),
    do: {:error, {:energy_switch_requires_different_targets, instance_id}}

  defp require_different_in_play_targets(_source_id, _target_id), do: :ok

  defp require_rare_candy_evolves_from(%{evolves_from: stage_1_id} = metadata, target) do
    with {:ok, stage_1_metadata} <- CardRegistry.fetch(stage_1_id),
         :ok <- require_basic_pokemon_target(target) do
      if stage_1_metadata.evolves_from == target.card_id do
        :ok
      else
        {:error,
         {:cannot_rare_candy, metadata.id, :expected_basic, stage_1_metadata.evolves_from, :got,
          target.card_id}}
      end
    end
  end

  defp require_basic_pokemon_target(%{card_id: card_id}) do
    with {:ok, metadata} <- CardRegistry.fetch(card_id) do
      require_basic_pokemon(metadata)
    end
  end

  defp require_poffin_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- CardRegistry.fetch(target.card_id),
           :ok <- require_basic_pokemon(metadata),
           true <-
             metadata.hp <= 70 ||
               {:error, {:poffin_target_hp_too_high, target.card_id, metadata.hp}} do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_basic_psychic_pokemon_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- CardRegistry.fetch(target.card_id),
           :ok <- require_basic_pokemon(metadata),
           :ok <- require_psychic_pokemon(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_psychic_pokemon(%{supertype: :pokemon, type: :psychic}), do: :ok
  defp require_psychic_pokemon(metadata), do: {:error, {:not_psychic_pokemon, metadata}}

  defp require_attachment_effect_params(
         %{id: "POR-088", effect: %{max_targets: max_targets}},
         params,
         state,
         player_id,
         %{type: :psychic}
       ) do
    target_ids = Map.get(params, :target_ids, [])

    cond do
      not is_list(target_ids) ->
        {:error, :telepathic_psychic_energy_targets_must_be_list}

      length(target_ids) > max_targets ->
        {:error, {:too_many_telepathic_psychic_energy_targets, length(target_ids), max_targets}}

      true ->
        with {:ok, targets} <- fetch_deck_cards(state, player_id, target_ids) do
          require_basic_psychic_pokemon_targets(targets)
        end
    end
  end

  defp require_attachment_effect_params(_metadata, _params, _state, _player_id, _target_metadata),
    do: :ok

  defp require_hammer_item(%{card_id: card_id}) when card_id in ["POR-071", "TWM-148"], do: :ok
  defp require_hammer_item(card), do: {:error, {:not_hammer_item, card.card_id}}

  defp require_hammer_coin_result(%{card_id: "POR-071"}, %{coin_result: result})
       when result in [:heads, :tails], do: :ok

  defp require_hammer_coin_result(%{card_id: "POR-071"}, %{coin_result: result}),
    do: {:error, {:invalid_coin_result, result}}

  defp require_hammer_coin_result(%{card_id: "POR-071"}, _params),
    do: {:error, :missing_coin_result}

  defp require_hammer_coin_result(_item, _params), do: :ok

  defp hammer_discards_energy?(%{card_id: "POR-071"}, %{coin_result: :heads}), do: true
  defp hammer_discards_energy?(%{card_id: "POR-071"}, %{coin_result: :tails}), do: false
  defp hammer_discards_energy?(_item, _params), do: true

  defp require_hammer_can_discard(%{card_id: "TWM-148"}, %{energy_type: :special}), do: :ok

  defp require_hammer_can_discard(%{card_id: "TWM-148"}, metadata),
    do: {:error, {:enhanced_hammer_requires_special_energy, metadata.id}}

  defp require_hammer_can_discard(%{card_id: "POR-071"}, _metadata), do: :ok

  defp require_pokemon_knocked_out_during_opponents_last_turn(%{
         pokemon_knocked_out_during_opponents_last_turn?: true
       }),
       do: :ok

  defp require_pokemon_knocked_out_during_opponents_last_turn(_player),
    do: {:error, :unfair_stamp_requires_ko_during_opponents_last_turn}

  defp require_team_rocket_pokemon_knocked_out_during_opponents_last_turn(%{
         team_rocket_pokemon_knocked_out_during_opponents_last_turn?: true
       }),
       do: :ok

  defp require_team_rocket_pokemon_knocked_out_during_opponents_last_turn(_player),
    do: {:error, :team_rockets_archer_requires_team_rocket_ko_during_opponents_last_turn}

  defp require_team_rocket_supporter_played_this_turn(%{markers: markers}) do
    if MapSet.member?(markers, :team_rocket_supporter_played_this_turn) do
      :ok
    else
      {:error, :team_rockets_factory_requires_team_rocket_supporter_played_this_turn}
    end
  end

  defp require_stadium_in_play(%{stadium: %{card_id: card_id}}, card_id), do: :ok

  defp require_stadium_in_play(%{stadium: nil}, expected_card_id),
    do: {:error, {:stadium_not_in_play, expected_card_id}}

  defp require_stadium_in_play(%{stadium: %{card_id: actual_card_id}}, expected_card_id),
    do: {:error, {:wrong_stadium_in_play, expected_card_id, actual_card_id}}

  defp require_different_energy_types(_hand_energy_metadata, nil), do: :ok

  defp require_different_energy_types(hand_energy_metadata, attach_energy_metadata) do
    hand_types = Map.get(hand_energy_metadata, :provides, [])
    attach_types = Map.get(attach_energy_metadata, :provides, [])

    if MapSet.disjoint?(MapSet.new(hand_types), MapSet.new(attach_types)) do
      :ok
    else
      {:error,
       {:crispin_energy_types_must_differ, hand_energy_metadata.id, attach_energy_metadata.id}}
    end
  end

  defp require_not_retreated_this_turn(%{retreated?: false}), do: :ok
  defp require_not_retreated_this_turn(_player), do: {:error, :already_retreated_this_turn}

  defp require_retreat_cost(pokemon, %{retreat_cost: cost}, attachments) do
    cost = effective_retreat_cost(cost, pokemon.tool)
    provided_types = Enum.flat_map(attachments, &attachment_provided_types/1)

    if length(attachments) == length(cost) and can_pay_cost?(cost, provided_types) do
      :ok
    else
      {:error, {:cannot_pay_retreat_cost, cost, provided_types}}
    end
  end

  defp require_retreat_cost(_pokemon, metadata, _attachments),
    do: {:error, {:missing_retreat_cost, metadata.id}}

  defp effective_retreat_cost(cost, %{card_id: "ASC-181"}), do: drop_colorless_cost(cost, 2)
  defp effective_retreat_cost(cost, _tool), do: cost

  defp drop_colorless_cost(cost, 0), do: cost

  defp drop_colorless_cost(cost, count) do
    case Enum.split_while(cost, &(&1 != :colorless)) do
      {_before_match, []} ->
        cost

      {before_match, [_colorless | after_match]} ->
        drop_colorless_cost(before_match ++ after_match, count - 1)
    end
  end

  defp require_ability(state, source, ability_id) do
    with {:ok, metadata} <- CardRegistry.fetch(source.card_id),
         :ok <- require_ability_hooks(state, source, metadata, ability_id),
         :ok <- require_ability_not_blocked_by_damp(state, metadata, ability_id),
         {:ok, abilities} <- Map.fetch(metadata, :abilities),
         {:ok, ability} <- Map.fetch(abilities, ability_id) do
      {:ok, Map.put(ability, :id, ability_id)}
    else
      :error ->
        {:error, {:unsupported_ability, source.card_id, ability_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_ability_hooks(state, source, metadata, ability_id) do
    state
    |> Hooks.run(:before_ability, %{source: source, metadata: metadata, ability_id: ability_id})
    |> require_hook_success()
  end

  defp require_ability_not_blocked_by_damp(state, metadata, ability_id) do
    case Map.fetch(metadata, :abilities) do
      {:ok, abilities} ->
        case Map.fetch(abilities, ability_id) do
          {:ok, %{effect: %{requires_self_knock_out?: true}}} ->
            if damp_active?(state),
              do: {:error, {:ability_blocked_by_damp, metadata.id, ability_id}},
              else: :ok

          {:ok, _ability} ->
            :ok

          :error ->
            :ok
        end

      :error ->
        :ok
    end
  end

  defp require_played_this_turn(%{turn_number: turn_number}, %{turn_entered_play: turn_number}),
    do: :ok

  defp require_played_this_turn(_state, source),
    do: {:error, {:pokemon_was_not_played_this_turn, source.instance_id}}

  defp require_marker_available(player, marker) do
    if MapSet.member?(player.markers, marker),
      do: {:error, {:marker_already_used, marker}},
      else: :ok
  end

  defp require_attached_energy_type(pokemon, type) do
    if attached_energy_type?(pokemon, type) do
      :ok
    else
      {:error, {:missing_attached_energy_type, pokemon.instance_id, type}}
    end
  end

  defp attached_energy_type?(pokemon, type) do
    Enum.any?(pokemon.attachments, fn attachment ->
      attachment.card_id
      |> CardRegistry.fetch!()
      |> Map.get(:provides, [])
      |> Enum.member?(type)
    end)
  end

  defp require_counter_count(counters, max_counters)
       when is_integer(counters) and counters >= 0 and counters <= max_counters, do: :ok

  defp require_counter_count(counters, max_counters),
    do: {:error, {:invalid_damage_counter_count, counters, max_counters}}

  defp require_available_damage_counters(pokemon, counters) do
    available = div(pokemon.damage, 10)

    if counters <= available do
      :ok
    else
      {:error, {:not_enough_damage_counters, pokemon.instance_id, counters, available}}
    end
  end

  defp require_same_player(player_id, player_id), do: :ok

  defp require_same_player(player_id, expected),
    do: {:error, {:wrong_player, :expected, expected, :got, player_id}}

  defp require_top_two_choice(%{deck: [chosen, other | _deck]}, chosen_id)
       when chosen.instance_id == chosen_id,
       do: {:ok, chosen, other}

  defp require_top_two_choice(%{deck: [other, chosen | _deck]}, chosen_id)
       when chosen.instance_id == chosen_id,
       do: {:ok, chosen, other}

  defp require_top_two_choice(%{deck: deck}, _chosen_id) when length(deck) < 2,
    do: {:error, :not_enough_cards_for_recon_directive}

  defp require_top_two_choice(_player, chosen_id),
    do: {:error, {:chosen_card_not_in_top_two, chosen_id}}

  defp require_active_pokemon_has_festival_lead_ability(state, player_id) do
    with {:ok, player} <- fetch_player(state, player_id),
         active when not is_nil(active) <- player.active,
         {:ok, active_metadata} <- Metadata.fetch(active.card_id) do
      active_metadata
      |> Map.get(:abilities, %{})
      |> Map.has_key?("festival_lead")
      |> case do
        true -> :ok
        false -> {:error, {:active_pokemon_missing_ability, active.instance_id, :festival_lead}}
      end
    else
      nil -> {:error, {:missing_active_pokemon, player_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_optional_card_in_top_deck(_state, _player_id, nil, _count, _action), do: :ok

  defp require_optional_card_in_top_deck(state, player_id, card, count, action) do
    with {:ok, player} <- fetch_player(state, player_id) do
      top_cards = Enum.take(player.deck, count)

      if Enum.any?(top_cards, &(&1.instance_id == card.instance_id)) do
        :ok
      else
        {:error, {:card_not_in_top_deck, action, card.instance_id, count}}
      end
    end
  end

  defp require_cards_in_top_deck(_state, _player_id, [], _count, _action), do: :ok

  defp require_cards_in_top_deck(state, player_id, cards, count, action) do
    with {:ok, player} <- fetch_player(state, player_id) do
      top_card_ids =
        player.deck
        |> Enum.take(count)
        |> MapSet.new(& &1.instance_id)

      Enum.reduce_while(cards, :ok, fn card, :ok ->
        if MapSet.member?(top_card_ids, card.instance_id) do
          {:cont, :ok}
        else
          {:halt, {:error, {:card_not_in_top_deck, action, card.instance_id, count}}}
        end
      end)
    end
  end

  defp require_max_target_ids(target_ids, max_targets, _action)
       when length(target_ids) <= max_targets, do: :ok

  defp require_max_target_ids(target_ids, max_targets, action),
    do: {:error, {:too_many_targets, action, length(target_ids), max_targets}}

  defp require_exact_target_ids(target_ids, target_count, _action)
       when length(target_ids) == target_count, do: :ok

  defp require_exact_target_ids(target_ids, target_count, action),
    do: {:error, {:wrong_target_count, action, length(target_ids), target_count}}

  defp require_unique_target_ids(target_ids, _action) do
    if length(target_ids) == length(Enum.uniq(target_ids)) do
      :ok
    else
      {:error, {:duplicate_target_ids, target_ids}}
    end
  end

  defp require_bug_catching_set_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- Metadata.fetch(target.card_id),
           :ok <- require_bug_catching_set_target(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_bug_catching_set_target(%Metadata{category: :pokemon, types: types} = metadata) do
    if :grass in types do
      :ok
    else
      {:error, {:invalid_bug_catching_set_target, metadata.id}}
    end
  end

  defp require_bug_catching_set_target(%Metadata{category: :energy, raw_effect: nil} = metadata) do
    if String.contains?(metadata.name, "Grass") do
      :ok
    else
      {:error, {:invalid_bug_catching_set_target, metadata.id}}
    end
  end

  defp require_bug_catching_set_target(metadata),
    do: {:error, {:invalid_bug_catching_set_target, metadata.id}}

  defp require_colorless_pokemon_with_100_hp_or_less_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- Metadata.fetch(target.card_id),
           :ok <- require_colorless_pokemon_with_100_hp_or_less_target(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_colorless_pokemon_with_100_hp_or_less_target(%Metadata{
         category: :pokemon,
         hp: hp,
         id: card_id,
         types: types
       })
       when is_integer(hp) do
    if :colorless in types and hp <= 100 do
      :ok
    else
      {:error, {:invalid_fan_call_target, card_id}}
    end
  end

  defp require_colorless_pokemon_with_100_hp_or_less_target(%Metadata{id: card_id}),
    do: {:error, {:invalid_fan_call_target, card_id}}

  defp require_optional_team_rocket_supporter_target(nil), do: :ok

  defp require_optional_team_rocket_supporter_target(target) do
    with {:ok, metadata} <- Metadata.fetch(target.card_id) do
      require_team_rocket_supporter_target(metadata)
    end
  end

  defp require_team_rocket_supporter_target(%Metadata{
         category: :trainer,
         trainer_type: :supporter,
         name: name
       }) do
    if String.contains?(name, "Team Rocket") do
      :ok
    else
      {:error, {:invalid_team_rockets_transceiver_target, name}}
    end
  end

  defp require_team_rocket_supporter_target(metadata),
    do: {:error, {:invalid_team_rockets_transceiver_target, metadata.id}}

  defp require_secret_box_discards_other_cards(secret_box_id, discard_ids) do
    if secret_box_id in discard_ids do
      {:error, :secret_box_must_discard_3_other_cards}
    else
      :ok
    end
  end

  defp require_secret_box_target_keys(target_ids_by_type) do
    invalid_target_types = Map.keys(target_ids_by_type) -- @secret_box_trainer_types

    case invalid_target_types do
      [] -> :ok
      invalid_target_types -> {:error, {:invalid_secret_box_target_types, invalid_target_types}}
    end
  end

  defp secret_box_target_ids(target_ids_by_type) do
    target_ids_by_type
    |> Map.take(@secret_box_trainer_types)
    |> Map.values()
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_secret_box_targets(state, player_id, target_ids_by_type) do
    Enum.reduce_while(@secret_box_trainer_types, {:ok, []}, fn trainer_type, {:ok, targets} ->
      case Map.get(target_ids_by_type, trainer_type) do
        nil ->
          {:cont, {:ok, targets}}

        instance_id ->
          case find_in_player_zone(state, player_id, :deck, instance_id) do
            {:ok, card} -> {:cont, {:ok, targets ++ [{trainer_type, card}]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp require_secret_box_targets(targets) do
    Enum.reduce_while(targets, :ok, fn {trainer_type, target}, :ok ->
      with {:ok, metadata} <- Metadata.fetch(target.card_id),
           :ok <- require_secret_box_target(metadata, trainer_type) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_secret_box_target(
         %Metadata{category: :trainer, trainer_type: actual_trainer_type},
         expected_trainer_type
       )
       when actual_trainer_type == expected_trainer_type, do: :ok

  defp require_secret_box_target(
         %Metadata{id: card_id, category: :trainer, trainer_type: actual_trainer_type},
         expected_trainer_type
       ),
       do:
         {:error,
          {:invalid_secret_box_target, card_id, expected_trainer_type, actual_trainer_type}}

  defp require_secret_box_target(%Metadata{id: card_id}, trainer_type),
    do: {:error, {:invalid_secret_box_target, card_id, trainer_type}}

  defp require_basic_team_rocket_pokemon_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- Metadata.fetch(target.card_id),
           :ok <- require_basic_team_rocket_pokemon_target(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_basic_team_rocket_pokemon_target(%Metadata{
         category: :pokemon,
         stage: :basic,
         name: name
       }) do
    if String.contains?(name, "Team Rocket") do
      :ok
    else
      {:error, {:invalid_team_rockets_proton_target, name}}
    end
  end

  defp require_basic_team_rocket_pokemon_target(metadata),
    do: {:error, {:invalid_team_rockets_proton_target, metadata.id}}

  defp require_pokemon_ex_targets(targets) do
    Enum.reduce_while(targets, :ok, fn target, :ok ->
      with {:ok, metadata} <- Metadata.fetch(target.card_id),
           :ok <- require_pokemon_ex_target(metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_pokemon_ex_target(%Metadata{category: :pokemon, rule_box?: true, suffix: "ex"}),
    do: :ok

  defp require_pokemon_ex_target(metadata),
    do: {:error, {:invalid_pokemon_ex_target, metadata.id}}

  defp require_mega_evolution_pokemon_ex(metadata) do
    category = Map.get(metadata, :supertype) || Map.get(metadata, :category)
    name = Map.get(metadata, :name)

    if category == :pokemon && is_binary(name) && String.starts_with?(name, "Mega ") &&
         String.ends_with?(name, " ex") do
      :ok
    else
      {:error, {:not_mega_evolution_pokemon_ex, metadata.id}}
    end
  end

  defp require_evolved_this_turn(%{turn_number: turn_number}, %{turn_entered_play: turn_number}),
    do: :ok

  defp require_evolved_this_turn(_state, source),
    do: {:error, {:pokemon_did_not_evolve_this_turn, source.instance_id}}

  defp require_evolves_from(%{evolves_from: card_id}, %{card_id: card_id}), do: :ok

  defp require_evolves_from(%{id: evolution_card_id, evolves_from: expected}, target),
    do: {:error, {:cannot_evolve, evolution_card_id, :expected, expected, :got, target.card_id}}

  defp require_evolves_from(%{id: evolution_card_id}, _target),
    do: {:error, {:card_is_not_evolution, evolution_card_id}}

  defp require_first_turn_evolution_allowed(%{turn_number: 1}),
    do: {:error, :cannot_evolve_on_first_turn_of_game}

  defp require_first_turn_evolution_allowed(_state), do: :ok

  defp require_can_evolve_this_turn(
         %{turn_number: turn_number} = state,
         %{turn_entered_play: turn_number} = target,
         evolution_metadata
       ) do
    if forest_of_vitality_allows_same_turn_evolution?(state, target, evolution_metadata) do
      :ok
    else
      {:error, :cannot_evolve_pokemon_played_this_turn}
    end
  end

  defp require_can_evolve_this_turn(_state, _target, _evolution_metadata), do: :ok

  defp forest_of_vitality_allows_same_turn_evolution?(
         %{turn_number: turn_number, stadium: %{card_id: "MEG-117"}},
         target,
         %{type: :grass}
       )
       when turn_number > 1 do
    case CardRegistry.fetch(target.card_id) do
      {:ok, %{type: :grass}} -> true
      _ -> false
    end
  end

  defp forest_of_vitality_allows_same_turn_evolution?(_state, _target, _evolution_metadata),
    do: false

  defp require_energy_attachment_available(%{energy_attached?: false}), do: :ok

  defp require_energy_attachment_available(_player),
    do: {:error, :energy_already_attached_this_turn}

  defp require_bench_space(%{bench: bench}) when length(bench) < 5, do: :ok
  defp require_bench_space(_player), do: {:error, :bench_full}

  defp find_in_player_zone(state, player_id, zone, instance_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      player
      |> Map.fetch!(zone)
      |> Enum.find(&(&1.instance_id == instance_id))
      |> case do
        nil -> {:error, {:card_not_found, player_id, zone, instance_id}}
        card -> {:ok, card}
      end
    end
  end

  defp optional_deck_card(_state, _player_id, nil), do: {:ok, nil}

  defp optional_deck_card(state, player_id, instance_id),
    do: find_in_player_zone(state, player_id, :deck, instance_id)

  defp optional_card_metadata(nil), do: {:ok, nil}
  defp optional_card_metadata(card), do: CardRegistry.fetch(card.card_id)

  defp optional_in_play_target(_state, _player_id, nil, nil), do: {:ok, nil}

  defp optional_in_play_target(_state, _player_id, nil, _card),
    do: {:error, :missing_attach_target}

  defp optional_in_play_target(state, player_id, target_id, _card),
    do: find_in_play(state, player_id, target_id)

  defp fetch_deck_cards(state, player_id, instance_ids) do
    instance_ids
    |> Enum.reduce_while({:ok, []}, fn instance_id, {:ok, cards} ->
      case find_in_player_zone(state, player_id, :deck, instance_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_discard_cards(state, player_id, instance_ids) do
    instance_ids
    |> Enum.reduce_while({:ok, []}, fn instance_id, {:ok, cards} ->
      case find_in_player_zone(state, player_id, :discard, instance_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_hand_cards(state, player_id, instance_ids) do
    instance_ids
    |> Enum.reduce_while({:ok, []}, fn instance_id, {:ok, cards} ->
      case find_in_player_zone(state, player_id, :hand, instance_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_in_play(state, player_id, instance_id) do
    with {:ok, player} <- fetch_player(state, player_id) do
      ([player.active] ++ player.bench)
      |> Enum.reject(&is_nil/1)
      |> Enum.find(&(&1.instance_id == instance_id))
      |> case do
        nil -> {:error, {:pokemon_not_in_play, player_id, instance_id}}
        card -> {:ok, card}
      end
    end
  end

  defp find_attachment(target, attachment_id) do
    target.attachments
    |> Enum.find(&(&1.instance_id == attachment_id))
    |> case do
      nil -> {:error, {:attachment_not_found, target.instance_id, attachment_id}}
      attachment -> {:ok, attachment}
    end
  end

  defp fetch_attachments(target, attachment_ids) do
    attachment_ids
    |> Enum.reduce_while({:ok, []}, fn attachment_id, {:ok, attachments} ->
      case find_attachment(target, attachment_id) do
        {:ok, attachment} -> {:cont, {:ok, [attachment | attachments]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, attachments} -> {:ok, Enum.reverse(attachments)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attachment_provided_types(attachment) do
    attachment.card_id
    |> CardRegistry.fetch!()
    |> Map.get(:provides, [])
  end

  defp reject_instance(cards, instance_id),
    do: Enum.reject(cards, &(&1.instance_id == instance_id))
end
