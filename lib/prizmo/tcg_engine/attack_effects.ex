defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  import Prizmo.TcgEngine.BoardState, only: [active_card: 2]
  import Prizmo.TcgEngine.CardStore, only: [cards_in_zone: 3, get_card: 2]
  import Prizmo.TcgEngine.Operation, only: [update: 3]

  import Prizmo.TcgEngine.Requirements,
    only: [require_card_owned_by_player: 2, require_card_zone: 2]

  alias Prizmo.TcgEngine.CardInstance

  @supported_effect_types [
    :bonus_damage_per_benched_pokemon,
    :bonus_damage_if_defender_pokemon_ex,
    :bonus_damage_if_attacker_has_team_rocket_energy,
    :bonus_damage_if_moved_from_bench_to_active_this_turn,
    :bonus_damage_per_energy_attached_to_both_active,
    :bonus_damage_per_energy_attached_to_defender,
    :damage_unaffected_by_effects_on_opponent_active,
    :damage_only_if_stadium_in_play,
    :damage_per_own_basic_pokemon_in_play,
    :damage_per_own_benched_pokemon,
    :damage_per_own_team_rocket_pokemon_in_play,
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

  @spec resolve_after_damage(String.t(), String.t(), CardInstance.t(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def resolve_after_damage(game_id, player_id, %CardInstance{} = attacker_card, attack, opts)
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
end
