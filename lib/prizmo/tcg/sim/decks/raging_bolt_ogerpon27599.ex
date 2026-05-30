defmodule Prizmo.Tcg.Sim.Decks.RagingBoltOgerpon27599 do
  @moduledoc """
  Compatibility shim for the shared Raging Bolt Ogerpon deck fixture.
  """

  alias Prizmo.Tcg.Decks.RagingBoltOgerpon27599, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
