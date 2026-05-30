defmodule Prizmo.Tcg.Sim.Decks.LopunnyDudunsparce27514 do
  @moduledoc """
  Compatibility shim for the shared Lopunny Dudunsparce deck fixture.
  """

  alias Prizmo.Tcg.Decks.LopunnyDudunsparce27514, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
