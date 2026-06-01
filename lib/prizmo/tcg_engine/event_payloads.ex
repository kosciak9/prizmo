defmodule Prizmo.TcgEngine.EventPayloads do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance

  def card_source(%CardInstance{} = card) do
    %{type: :card, card_id: card.card_id, card_instance_id: card.id}
  end

  def moved_cards(cards, from_zone, to_zone) do
    Enum.map(cards, fn card ->
      %{
        instance_id: card.id,
        card_id: card.card_id,
        owner_player_id: card.owner_player_id,
        from_zone: from_zone,
        to_zone: to_zone,
        to_position: card.position
      }
    end)
  end
end
