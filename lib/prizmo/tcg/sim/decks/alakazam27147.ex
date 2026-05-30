defmodule Prizmo.Tcg.Sim.Decks.Alakazam27147 do
  @moduledoc """
  Compatibility shim for the shared Alakazam/Dudunsparce deck fixture.
  """

  alias Prizmo.Tcg.Decks.Alakazam27147, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
