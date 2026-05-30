defmodule Prizmo.Tcg.Sim.Decks.FestivalLead27445 do
  @moduledoc """
  Compatibility shim for the shared Festival Lead deck fixture.
  """

  alias Prizmo.Tcg.Decks.FestivalLead27445, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
