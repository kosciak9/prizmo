defmodule Prizmo.Tcg.Sim.PlayerState do
  @moduledoc """
  Player-owned state for a simulated Pokémon TCG game.
  """

  @enforce_keys [:id]
  defstruct [
    :id,
    expected_card_count: nil,
    deck: [],
    hand: [],
    prizes: [],
    discard: [],
    lost_zone: [],
    active: nil,
    bench: [],
    mulligans_taken: 0,
    mulligan_bonus_draws_taken: 0,
    markers: MapSet.new(),
    supporter_played?: false,
    item_cards_locked?: false,
    energy_attached?: false,
    retreated?: false,
    pokemon_knocked_out_during_opponents_last_turn?: false,
    team_rocket_pokemon_knocked_out_during_opponents_last_turn?: false
  ]
end
