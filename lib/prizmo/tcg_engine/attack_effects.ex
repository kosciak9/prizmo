defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [active_card: 2]

  import Prizmo.TcgEngine.CardStore,
    only: [
      cards_in_zone: 3,
      deck_cards_for_player: 2,
      discard_cards_from_hand: 3,
      get_card: 2,
      next_hand_position_result: 2
    ]

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [require_card_owned_by_player: 2, require_card_zone: 2]

  alias Prizmo.TcgEngine.AttackLocks
  alias Prizmo.TcgEngine.BattleActions
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.TurnStore

  @supported_effect_types [
    :bonus_damage_per_benched_pokemon,
    :bonus_damage_if_defender_pokemon_ex,
    :bonus_damage_if_attacker_has_team_rocket_energy,
    :bonus_damage_if_moved_from_bench_to_active_this_turn,
    :bonus_damage_per_energy_attached_to_both_active,
    :bonus_damage_per_energy_attached_to_defender,
    :attacker_cannot_attack_next_turn,
    :confuse_defender_active,
    :damage_unaffected_by_effects_on_opponent_active,
    :damage_only_if_stadium_in_play,
    :discard_hand_then_draw,
    :draw_after_attack,
    :damage_per_own_basic_pokemon_in_play,
    :damage_per_own_benched_pokemon,
    :damage_per_own_team_rocket_pokemon_in_play,
    :self_damage,
    :switch_self_with_bench
  ]

  @spec supported?(nil | map()) :: boolean()
  def supported?(nil), do: true

  def supported?(%{type: effect_type}) do
    effect_type in @supported_effect_types
  end

  def supported?(_effect), do: false

  @spec type(term()) :: term()
  def type(%{type: effect_type}), do: effect_type
  def type(effect), do: effect

  @spec resolve_after_damage(
          String.t(),
          String.t(),
          CardInstance.t(),
          CardInstance.t(),
          map(),
          map()
        ) ::
          {:ok, map()} | {:error, term()}
  def resolve_after_damage(
        game_id,
        player_id,
        %CardInstance{} = attacker_card,
        %CardInstance{} = defender_card,
        attack,
        opts
      )
      when is_binary(game_id) and is_binary(player_id) and is_map(attack) and is_map(opts) do
    case Map.get(attack, :effect) do
      %{type: :switch_self_with_bench} ->
        switch_self_with_bench(game_id, player_id, attacker_card, opts)

      %{type: :bonus_damage_if_defender_pokemon_ex} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_attacker_has_team_rocket_energy} ->
        {:ok, %{}}

      %{type: :bonus_damage_if_moved_from_bench_to_active_this_turn} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_benched_pokemon} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_energy_attached_to_both_active} ->
        {:ok, %{}}

      %{type: :bonus_damage_per_energy_attached_to_defender} ->
        {:ok, %{}}

      %{type: :attacker_cannot_attack_next_turn} ->
        attacker_cannot_attack_next_turn(game_id, attacker_card)

      %{type: :confuse_defender_active} ->
        set_defender_status(game_id, defender_card, :confused)

      %{type: :damage_per_own_benched_pokemon} ->
        {:ok, %{}}

      %{type: :damage_per_own_basic_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_only_if_stadium_in_play} ->
        {:ok, %{}}

      %{type: :damage_per_own_team_rocket_pokemon_in_play} ->
        {:ok, %{}}

      %{type: :damage_unaffected_by_effects_on_opponent_active} ->
        {:ok, %{}}

      %{type: :discard_hand_then_draw, count: count} when is_integer(count) and count >= 0 ->
        discard_hand_then_draw(game_id, player_id, count)

      %{type: :draw_after_attack, count: count} when is_integer(count) and count >= 0 ->
        draw_after_attack(game_id, player_id, count)

      %{type: :self_damage, damage: damage} when is_integer(damage) and damage >= 0 ->
        self_damage(game_id, player_id, attacker_card, damage)

      nil ->
        {:ok, %{}}

      effect ->
        {:error, {:unsupported_attack_effect, type(effect)}}
    end
  end

  defp switch_self_with_bench(game_id, player_id, %CardInstance{} = attacker_card, opts) do
    with {:ok, bench_card} <- switch_target(game_id, player_id, opts) do
      switch_attacker_with_bench(game_id, player_id, attacker_card, bench_card)
    end
  end

  defp self_damage(game_id, player_id, %CardInstance{} = attacker_card, damage) do
    with {:ok, damage_result} <-
           BattleActions.apply_attack_damage(game_id, player_id, attacker_card, damage) do
      {:ok,
       %{
         effect_type: "self_damage",
         self_damage_card_instance_id: attacker_card.id,
         self_damage: damage_result.damage,
         self_resulting_damage: damage_result.resulting_damage,
         self_knocked_out?: damage_result.knocked_out?
       }}
    end
  end

  defp draw_after_attack(game_id, player_id, count) do
    with {:ok, player} <- PlayerStore.get_player(game_id, player_id),
         {:ok, deck_cards} <- deck_cards_for_player(player.id, count),
         {:ok, drawn_cards} <- draw_cards_to_hand(game_id, player_id, deck_cards) do
      {:ok,
       %{
         effect_type: "draw_after_attack",
         requested_draw_count: count,
         drawn_count: length(drawn_cards)
       }}
    end
  end

  defp attacker_cannot_attack_next_turn(game_id, %CardInstance{} = attacker_card) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         markers = AttackLocks.put_cannot_attack_next_turn_marker(attacker_card, turn),
         {:ok, _attacker_card} <- update(attacker_card, :set_markers, %{markers: markers}) do
      {:ok,
       %{
         effect_type: "attacker_cannot_attack_next_turn",
         cannot_attack_card_instance_id: attacker_card.id,
         blocked_turn_number: turn.turn_number + 2
       }}
    end
  end

  defp set_defender_status(game_id, %CardInstance{} = defender_card, status) do
    with {:ok, current_defender_card} <- get_card(game_id, defender_card.id) do
      case current_defender_card.zone do
        :active ->
          with {:ok, _defender_card} <-
                 update(current_defender_card, :set_status, %{status: status}) do
            {:ok,
             %{
               effect_type: "confuse_defender_active",
               defender_status: Atom.to_string(status),
               defender_status_applied?: true,
               defender_status_card_instance_id: current_defender_card.id
             }}
          end

        _other_zone ->
          {:ok,
           %{
             effect_type: "confuse_defender_active",
             defender_status: Atom.to_string(status),
             defender_status_applied?: false,
             defender_status_card_instance_id: defender_card.id
           }}
      end
    end
  end

  defp discard_hand_then_draw(game_id, player_id, count) do
    with {:ok, hand_cards} <- cards_in_zone(game_id, player_id, :hand),
         {:ok, discarded_cards} <- discard_cards_from_hand(game_id, player_id, hand_cards),
         {:ok, player} <- PlayerStore.get_player(game_id, player_id),
         {:ok, deck_cards} <- deck_cards_for_player(player.id, count),
         {:ok, drawn_cards} <- draw_cards_to_hand(game_id, player_id, deck_cards) do
      {:ok,
       %{
         effect_type: "discard_hand_then_draw",
         discarded_count: length(discarded_cards),
         requested_draw_count: count,
         drawn_count: length(drawn_cards)
       }}
    end
  end

  defp draw_cards_to_hand(_game_id, _player_id, []), do: {:ok, []}

  defp draw_cards_to_hand(game_id, player_id, deck_cards) do
    with {:ok, first_hand_position} <- next_hand_position_result(game_id, player_id) do
      deck_cards
      |> Enum.with_index(first_hand_position)
      |> Enum.map(fn {card, position} ->
        update(card, :draw_to_hand, %{position: position})
      end)
      |> collect_results()
    end
  end

  defp switch_target(game_id, player_id, opts) do
    case switch_bench_card_instance_id(opts) do
      nil ->
        implicit_switch_target(game_id, player_id)

      card_instance_id when is_binary(card_instance_id) ->
        explicit_switch_target(game_id, player_id, card_instance_id)

      _invalid ->
        {:error, :invalid_switch_bench_card_instance_id}
    end
  end

  defp switch_bench_card_instance_id(opts) do
    Map.get(opts, :switch_bench_card_instance_id) ||
      Map.get(opts, "switch_bench_card_instance_id")
  end

  defp implicit_switch_target(game_id, player_id) do
    with {:ok, bench_cards} <- cards_in_zone(game_id, player_id, :bench) do
      case bench_cards do
        [] -> {:ok, nil}
        [bench_card] -> {:ok, bench_card}
        [_first | _rest] -> {:error, :switch_self_with_bench_requires_target}
      end
    end
  end

  defp explicit_switch_target(game_id, player_id, card_instance_id) do
    with {:ok, bench_card} <- get_card(game_id, card_instance_id),
         :ok <- require_card_owned_by_player(bench_card, player_id),
         :ok <- require_card_zone(bench_card, :bench) do
      {:ok, bench_card}
    end
  end

  defp switch_attacker_with_bench(_game_id, _player_id, _attacker_card, nil) do
    {:ok, %{effect_type: "switch_self_with_bench", switched?: false}}
  end

  defp switch_attacker_with_bench(
         game_id,
         player_id,
         %CardInstance{} = attacker_card,
         %CardInstance{} = bench_card
       ) do
    with {:ok, active_card} <- active_card(game_id, player_id),
         :ok <- require_same_card(active_card, attacker_card),
         bench_position = bench_card.position,
         {:ok, _active_card} <-
           update(active_card, :move_active_to_bench, %{position: bench_position, status: nil}),
         {:ok, _bench_card} <-
           update(bench_card, :promote_to_active, %{position: 1, status: nil}) do
      {:ok,
       %{
         effect_type: "switch_self_with_bench",
         switched?: true,
         switched_active_card_instance_id: active_card.id,
         switched_bench_card_instance_id: bench_card.id
       }}
    end
  end

  defp require_same_card(%CardInstance{id: id}, %CardInstance{id: id}), do: :ok

  defp require_same_card(%CardInstance{}, %CardInstance{}),
    do: {:error, :attacker_is_no_longer_active}

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
end
