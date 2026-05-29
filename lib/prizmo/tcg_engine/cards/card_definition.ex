defmodule Prizmo.TcgEngine.Cards.CardDefinition do
  @moduledoc false

  @enforce_keys [:id, :kind, :play_window]
  defstruct [:id, :kind, :trainer_type, :play_window, costs: [], effects: [], hooks: []]
end
