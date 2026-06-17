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
         {:ok, player} <- CardStore.get_player(game_id, player_id),
         {:ok, opponent} <- CardStore.get_opponent(game_id, player_id) do
      base_cost = base_cost ++ additional_cost

      reduced_cost =
        if has_radiant_tsareena?(attached_cards) and
             player.prizes_remaining > opponent.prizes_remaining do
          remove_one_colorless(base_cost)
        else
          base_cost
        end

      {:ok, reduced_cost}
    else
      _ -> {:ok, base_cost}
    end
  end

  defp has_radiant_tsareena?(attached_cards) do
    Enum.any?(attached_cards, &(&1.card_id == "SSP-169"))
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
