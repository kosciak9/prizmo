defmodule Prizmo.TcgEngine.BattleActions do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [pokemon_hp: 1, require_energy: 1]
  import Prizmo.TcgEngine.Operation, only: [update: 3]
  import Prizmo.TcgEngine.Requirements, only: [require_attached_to: 2, require_card_zone: 2]

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
