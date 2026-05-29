defmodule Prizmo.Tcg.Sim.CardInstance do
  @moduledoc """
  A physical card in a simulated game.
  """

  @enforce_keys [:instance_id, :card_id, :owner]
  defstruct [
    :instance_id,
    :card_id,
    :owner,
    lifecycle: :in_deck,
    zone: :deck,
    attachments: [],
    damage: 0,
    status: nil,
    tool: nil,
    evolved_from: [],
    turn_entered_play: nil
  ]
end
