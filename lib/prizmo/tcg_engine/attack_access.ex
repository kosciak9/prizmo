defmodule Prizmo.TcgEngine.AttackAccess do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  @memory_dive_card_id "TEF-084"

  @doc "Fetches an executable attack the card instance can currently use."
  def fetch_attack(game_id, %CardInstance{} = attacker_card, attack_id)
      when is_binary(game_id) and (is_atom(attack_id) or is_binary(attack_id)) do
    with {:error, current_reason} <- CardCatalog.fetch_attack(attacker_card.card_id, attack_id) do
      fetch_memory_dive_attack(game_id, attacker_card, attack_id, current_reason)
    end
  end

  @doc "Returns executable attacks the card instance can currently declare."
  def executable_attacks(game_id, %CardInstance{} = attacker_card) when is_binary(game_id) do
    with {:ok, card} <- CardCatalog.fetch(attacker_card.card_id),
         current_attacks = Map.get(card, :attacks, %{}),
         {:ok, previous_attacks} <- memory_dive_executable_attacks(game_id, attacker_card) do
      current_attacks = executable_attack_entries(current_attacks, attacker_card.card_id)
      attacks = unique_by_attack_id(current_attacks ++ previous_attacks)

      {:ok, attacks}
    end
  end

  def memory_dive_active?(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    case CardStore.list_cards(game_id) do
      {:ok, cards} -> memory_dive_active?(cards, player_id)
      {:error, _reason} -> false
    end
  end

  def memory_dive_active?(cards, player_id) when is_list(cards) and is_binary(player_id) do
    Enum.any?(cards, fn card ->
      match?(
        %CardInstance{
          card_id: @memory_dive_card_id,
          owner_player_id: ^player_id,
          zone: zone
        }
        when zone in [:active, :bench],
        card
      )
    end)
  end

  def previous_evolution_cards(game_id, %CardInstance{} = attacker_card)
      when is_binary(game_id) do
    collect_previous_evolution_cards(game_id, attacker_card.evolves_from_card_instance_id, [])
  end

  defp fetch_memory_dive_attack(game_id, attacker_card, attack_id, current_reason) do
    with true <- memory_dive_active?(game_id, attacker_card.owner_player_id),
         {:ok, previous_cards} <- previous_evolution_cards(game_id, attacker_card) do
      previous_cards
      |> Enum.find_value(fn card ->
        case CardCatalog.fetch_attack(card.card_id, attack_id) do
          {:ok, attack} -> {:ok, Map.put(attack, :source_card_id, card.card_id)}
          {:error, _reason} -> nil
        end
      end)
      |> case do
        nil -> {:error, current_reason}
        result -> result
      end
    else
      false -> {:error, current_reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp memory_dive_executable_attacks(game_id, %CardInstance{} = attacker_card) do
    with true <- memory_dive_active?(game_id, attacker_card.owner_player_id),
         {:ok, previous_cards} <- previous_evolution_cards(game_id, attacker_card) do
      {:ok, Enum.flat_map(previous_cards, &executable_attack_entries_for_card/1)}
    else
      false -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_previous_evolution_cards(_game_id, nil, acc), do: {:ok, Enum.reverse(acc)}

  defp collect_previous_evolution_cards(game_id, card_instance_id, acc) do
    with {:ok, card} <- CardStore.get_card(game_id, card_instance_id) do
      collect_previous_evolution_cards(game_id, card.evolves_from_card_instance_id, [card | acc])
    end
  end

  defp executable_attack_entries_for_card(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{attacks: attacks}} -> executable_attack_entries(attacks, card_id)
      _other -> []
    end
  end

  defp executable_attack_entries(attacks, card_id) when is_map(attacks) do
    attacks
    |> Enum.sort_by(fn {attack_id, _attack} -> Atom.to_string(attack_id) end)
    |> Enum.flat_map(fn {attack_id, _catalog_attack} ->
      case CardCatalog.fetch_attack(card_id, attack_id) do
        {:ok, attack} -> [{attack_id, Map.put(attack, :source_card_id, card_id)}]
        {:error, _reason} -> []
      end
    end)
  end

  defp unique_by_attack_id(attacks) do
    {_seen, unique} =
      Enum.reduce(attacks, {MapSet.new(), []}, fn {attack_id, attack}, {seen, unique} ->
        if MapSet.member?(seen, attack_id) do
          {seen, unique}
        else
          {MapSet.put(seen, attack_id), [{attack_id, attack} | unique]}
        end
      end)

    Enum.reverse(unique)
  end
end
