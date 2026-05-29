defmodule Prizmo.TcgEngine.CardCatalog do
  @moduledoc false

  # This is the engine-owned boundary for read-only card metadata. It currently
  # delegates to the existing static catalog while the persisted engine migrates
  # card definitions behind this API.

  alias Prizmo.Tcg.Sim.CardRegistry

  defdelegate basic_pokemon?(card_id), to: CardRegistry
  defdelegate fetch(card_id), to: CardRegistry
  defdelegate fetch!(card_id), to: CardRegistry
  defdelegate fetch_attack(card_id, attack_id), to: CardRegistry
end
