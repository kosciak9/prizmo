defmodule Prizmo.Tcg.Sim.Decks.Dragapult27431 do
  @moduledoc """
  Compatibility shim for the shared Dragapult deck fixture.
  """

  alias Prizmo.Tcg.Decks.Dragapult27431, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
