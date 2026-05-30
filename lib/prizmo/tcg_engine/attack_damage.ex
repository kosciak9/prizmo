defmodule Prizmo.TcgEngine.AttackDamage do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance

  @spec damage_for(CardInstance.t(), CardInstance.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def damage_for(%CardInstance{} = attacker_card, %CardInstance{} = defender_card, attack)
      when is_map(attack) do
    with {:ok, damage} <- base_damage(attack) do
      apply_effect(damage, attacker_card, defender_card, Map.get(attack, :effect))
    end
  end

  defp base_damage(%{damage: damage}) when is_integer(damage) and damage >= 0, do: {:ok, damage}
  defp base_damage(%{damage: nil}), do: {:ok, 0}
  defp base_damage(attack) when not is_map_key(attack, :damage), do: {:ok, 0}
  defp base_damage(%{damage: damage}), do: {:error, {:unsupported_attack_damage, damage}}

  defp apply_effect(damage, _attacker_card, %CardInstance{} = defender_card, %{
         type: :bonus_damage_if_defender_pokemon_ex,
         bonus_damage: bonus_damage
       })
       when is_integer(bonus_damage) and bonus_damage >= 0 do
    with {:ok, defender_metadata} <- CardCatalog.fetch(defender_card.card_id) do
      if pokemon_ex?(defender_metadata) do
        {:ok, damage + bonus_damage}
      else
        {:ok, damage}
      end
    end
  end

  defp apply_effect(damage, _attacker_card, _defender_card, _effect), do: {:ok, damage}

  defp pokemon_ex?(%{supertype: :pokemon, suffix: "ex"}), do: true

  defp pokemon_ex?(%{supertype: :pokemon, name: name}) when is_binary(name) do
    String.ends_with?(name, " ex")
  end

  defp pokemon_ex?(_metadata), do: false
end
