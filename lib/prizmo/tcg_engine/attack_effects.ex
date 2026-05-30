defmodule Prizmo.TcgEngine.AttackEffects do
  @moduledoc false

  @supported_effect_types [
    :bonus_damage_if_defender_pokemon_ex
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
end
