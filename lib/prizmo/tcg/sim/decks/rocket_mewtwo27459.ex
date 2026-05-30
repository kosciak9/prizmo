defmodule Prizmo.Tcg.Sim.Decks.RocketMewtwo27459 do
  @moduledoc """
  Compatibility shim for the shared Rocket's Mewtwo deck fixture.
  """

  alias Prizmo.Tcg.Decks.RocketMewtwo27459, as: Deck

  defdelegate id(), to: Deck
  defdelegate name(), to: Deck
  defdelegate source_url(), to: Deck
  defdelegate counts(), to: Deck
  defdelegate card_ids(), to: Deck
end
