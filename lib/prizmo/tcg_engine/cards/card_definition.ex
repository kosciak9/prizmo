defmodule Prizmo.TcgEngine.Cards.CardDefinition do
  @moduledoc false

  @enforce_keys [:id, :kind, :play_window]
  defstruct [
    :id,
    :kind,
    :trainer_type,
    :play_window,
    first_turn_supporter_allowed_when_going_first?: false,
    costs: [],
    effects: [],
    hooks: []
  ]
end
