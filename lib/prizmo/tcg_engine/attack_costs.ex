defmodule Prizmo.TcgEngine.AttackCosts do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.StadiumEffects

  def require_attack_cost_paid(game_id, %CardInstance{} = attacker_card, attack)
      when is_binary(game_id) and is_map(attack) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, attacker_card.id),
         {:ok, effective_cost} <- effective_attack_cost(game_id, attacker_card, attack) do
      if paid?(effective_cost, attached_cards) do
        :ok
      else
        {:error, {:insufficient_attack_energy, stringify_cost(effective_cost)}}
      end
    end
  end

  def paid?(cost, attached_cards) when is_list(cost) and is_list(attached_cards) do
    cost
    |> normalize_cost()
    |> pay_with(attached_energy_providers(attached_cards))
  end

  def attack_cost(%{cost: cost}) when is_list(cost), do: normalize_cost(cost)
  def attack_cost(_attack), do: []

  @doc """
  Returns the effective attack cost after applying Tool reductions such as
  Radiant Tsareena (SSP-169): reduce Colorless cost by 1 when the player has
  more Prizes remaining than the opponent.
  """
  def effective_attack_cost(
        game_id,
        %CardInstance{owner_player_id: player_id} = attacker_card,
        attack
      )
      when is_binary(game_id) and is_map(attack) do
    base_cost = attack_cost(attack)

    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, attacker_card.id),
         {:ok, additional_cost} <- StadiumEffects.additional_attack_cost(game_id, attacker_card),
         {:ok, opponent} <- CardStore.get_opponent(game_id, player_id),
         {:ok, player_prize_count} <- prize_count(game_id, player_id),
         {:ok, opponent_prize_count} <- prize_count(game_id, opponent.player_id) do
      base_cost = base_cost ++ additional_cost

      reduced_cost =
        base_cost
        |> maybe_apply_radiant_tsareena(attached_cards, player_prize_count, opponent_prize_count)
        |> maybe_apply_seasoned_skill(attacker_card, attack, player_prize_count)

      {:ok, reduced_cost}
    else
      _ -> {:ok, base_cost}
    end
  end

  defp maybe_apply_radiant_tsareena(
         cost,
         attached_cards,
         player_prize_count,
         opponent_prize_count
       )
       when is_integer(player_prize_count) and is_integer(opponent_prize_count) do
    if has_radiant_tsareena?(attached_cards) and player_prize_count > opponent_prize_count do
      remove_colorless(cost, 1)
    else
      cost
    end
  end

  defp maybe_apply_seasoned_skill(
         cost,
         %CardInstance{} = attacker_card,
         attack,
         player_prize_count
       )
       when is_integer(player_prize_count) do
    remove_colorless(
      cost,
      seasoned_skill_reduction_count(attacker_card, attack, player_prize_count)
    )
  end

  defp seasoned_skill_reduction_count(
         %CardInstance{card_id: card_id},
         %{id: :blood_moon},
         player_prize_count
       )
       when is_integer(player_prize_count) and player_prize_count >= 0 do
    with {:ok, %{abilities: abilities}} <- CardCatalog.fetch(card_id),
         %{effect: %{type: :reduce_attack_cost_by_colorless_per_opponent_prize_taken}} <-
           Map.get(abilities, :seasoned_skill) do
      max(6 - player_prize_count, 0)
    else
      _other -> 0
    end
  end

  defp seasoned_skill_reduction_count(_attacker_card, _attack, _player), do: 0

  defp has_radiant_tsareena?(attached_cards) do
    Enum.any?(attached_cards, &(&1.card_id == "SSP-169"))
  end

  defp remove_colorless(cost, count) when is_integer(count) and count > 0 do
    Enum.reduce(1..count, cost, fn _, reduced_cost -> remove_one_colorless(reduced_cost) end)
  end

  defp remove_colorless(cost, _count), do: cost

  defp prize_count(game_id, player_id) do
    with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player_id, :prize) do
      {:ok, length(prizes)}
    end
  end

  defp remove_one_colorless(cost) do
    case Enum.split_while(cost, &(&1 != :colorless)) do
      {before, []} -> before
      {before, [:colorless | after_colorless]} -> before ++ after_colorless
    end
  end

  def stringify_cost(cost) when is_list(cost) do
    cost
    |> normalize_cost()
    |> Enum.map(&Atom.to_string/1)
  end

  defp normalize_cost(cost) do
    Enum.map(cost, fn
      type when is_atom(type) -> type
      type when is_binary(type) -> String.to_existing_atom(type)
    end)
  end

  defp attached_energy_providers(attached_cards) do
    Enum.flat_map(attached_cards, &energy_providers/1)
  end

  defp energy_providers(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, name: "Team Rocket's Energy"}} ->
        List.duplicate(%{card_instance_id: card.id, provides: [:psychic, :darkness]}, 2)

      {:ok, %{supertype: :energy, provides: provides}}
      when is_list(provides) and provides != [] ->
        [%{card_instance_id: card.id, provides: provides}]

      {:ok, %{supertype: :energy}} ->
        []

      {:ok, _metadata} ->
        []

      {:error, _reason} ->
        []
    end
  end

  defp pay_with(cost, providers) do
    cost
    |> Enum.sort_by(fn type -> if type == :colorless, do: 1, else: 0 end)
    |> Enum.reduce_while(providers, fn type, remaining_providers ->
      case pay_one(type, remaining_providers) do
        {:ok, remaining_providers} -> {:cont, remaining_providers}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> false
      _remaining_providers -> true
    end
  end

  defp pay_one(:colorless, providers) do
    case providers do
      [_provider | remaining_providers] -> {:ok, remaining_providers}
      [] -> :error
    end
  end

  defp pay_one(type, providers) do
    case Enum.split_while(providers, &(type not in &1.provides)) do
      {_before, []} ->
        :error

      {before, [_provider | after_provider]} ->
        {:ok, before ++ after_provider}
    end
  end
end
