defmodule Prizmo.TcgEngine.BattleActions do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [pokemon_hp: 1, require_energy: 1]
  import Prizmo.TcgEngine.Operation, only: [update: 3]
  import Prizmo.TcgEngine.Requirements, only: [require_attached_to: 2, require_card_zone: 2]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  def attached_energy_cards_for_retreat(game_id, active_card_id, energy_card_instance_ids) do
    energy_card_instance_ids
    |> Enum.map(fn energy_card_instance_id ->
      with {:ok, card} <- CardStore.get_card(game_id, energy_card_instance_id),
           :ok <- require_card_zone(card, :attached),
           :ok <- require_attached_to(card, active_card_id),
           :ok <- require_energy(card.card_id) do
        {:ok, card}
      end
    end)
    |> collect_results()
  end

  def discard_retreat_energy(game_id, player_id, energy_cards) do
    energy_cards
    |> Enum.map(fn energy_card ->
      with {:ok, position} <- CardStore.next_discard_position(game_id, player_id) do
        update(energy_card, :discard, %{position: position, attached_to_card_instance_id: nil})
      end
    end)
    |> collect_results()
  end

  def knockout_prize_count(%CardInstance{} = target_card) do
    with {:ok, card} <- CardCatalog.fetch(target_card.card_id) do
      {:ok, prize_count_for_card(card)}
    end
  end

  def take_knockout_prizes(_game_id, _player_id, 0), do: {:ok, []}

  def take_knockout_prizes(game_id, player_id, count)
      when is_binary(game_id) and is_binary(player_id) and is_integer(count) and count > 0 do
    with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player_id, :prize) do
      prizes
      |> Enum.take(count)
      |> Enum.map(fn prize_card ->
        with {:ok, position} <- CardStore.next_hand_position_result(game_id, player_id) do
          update(prize_card, :take_prize, %{position: position})
        end
      end)
      |> collect_results()
    end
  end

  def resolve_replacement_active_after_knockout(game_id, player_id)
      when is_binary(game_id) and is_binary(player_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      replacement_resolution(active_cards, bench_cards)
    end
  end

  def apply_attack_damage(game_id, attacking_player_id, target_card, damage) do
    damage = damage || 0

    with {:ok, target_hp} <- pokemon_hp(target_card.card_id),
         new_damage = target_card.damage + damage,
         {:ok, _target_card} <- update(target_card, :set_damage, %{damage: new_damage}),
         {:ok, knocked_out?} <-
           maybe_knock_out(game_id, attacking_player_id, target_card, new_damage, target_hp) do
      {:ok,
       %{
         damage: damage,
         resulting_damage: new_damage,
         knocked_out?: knocked_out?
       }}
    end
  end

  defp maybe_knock_out(_game_id, _attacking_player_id, _target_card, new_damage, target_hp)
       when new_damage < target_hp do
    {:ok, false}
  end

  defp maybe_knock_out(game_id, _attacking_player_id, target_card, _new_damage, _target_hp) do
    with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, target_card) do
      {:ok, true}
    end
  end

  defp replacement_resolution([_active_card | _rest], _bench_cards) do
    {:ok,
     %{
       empty_board?: false,
       promoted_card_instance_id: nil,
       replacement_required?: false
     }}
  end

  defp replacement_resolution([], []) do
    {:ok,
     %{
       empty_board?: true,
       promoted_card_instance_id: nil,
       replacement_required?: false
     }}
  end

  defp replacement_resolution([], [bench_card]) do
    with {:ok, promoted_card} <-
           update(bench_card, :promote_to_active, %{position: 1, status: nil}) do
      {:ok,
       %{
         empty_board?: false,
         promoted_card_instance_id: promoted_card.id,
         replacement_required?: false
       }}
    end
  end

  defp replacement_resolution([], bench_cards) do
    {:ok,
     %{
       empty_board?: false,
       promoted_card_instance_id: nil,
       replacement_candidate_card_instance_ids: Enum.map(bench_cards, & &1.id),
       replacement_required?: true
     }}
  end

  defp prize_count_for_card(%{supertype: :pokemon, suffix: "ex"}), do: 2

  defp prize_count_for_card(%{supertype: :pokemon, name: name}) when is_binary(name) do
    if String.ends_with?(name, " ex"), do: 2, else: 1
  end

  defp prize_count_for_card(_card), do: 1

  defp discard_knocked_out_stack(game_id, %CardInstance{} = target_card) do
    with {:ok, stack_cards} <- CardStore.attached_cards(game_id, target_card.id) do
      [target_card | stack_cards]
      |> Enum.map(fn card ->
        with {:ok, position} <- CardStore.next_discard_position(game_id, card.owner_player_id) do
          update(card, :discard, %{
            position: position,
            damage: 0,
            status: nil,
            attached_to_card_instance_id: nil,
            evolves_from_card_instance_id: nil
          })
        end
      end)
      |> collect_results()
    end
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
end
