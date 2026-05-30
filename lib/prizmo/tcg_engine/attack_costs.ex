defmodule Prizmo.TcgEngine.AttackCosts do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  def require_attack_cost_paid(game_id, %CardInstance{} = attacker_card, attack)
      when is_binary(game_id) and is_map(attack) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, attacker_card.id) do
      cost = attack_cost(attack)

      if paid?(cost, attached_cards) do
        :ok
      else
        {:error, {:insufficient_attack_energy, stringify_cost(cost)}}
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
    attached_cards
    |> Enum.map(&energy_provider/1)
    |> Enum.reject(&is_nil/1)
  end

  defp energy_provider(%CardInstance{} = card) do
    case CardCatalog.fetch(card.card_id) do
      {:ok, %{supertype: :energy, provides: provides}}
      when is_list(provides) and provides != [] ->
        %{card_instance_id: card.id, provides: provides}

      {:ok, %{supertype: :energy}} ->
        nil

      {:ok, _metadata} ->
        nil

      {:error, _reason} ->
        nil
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
