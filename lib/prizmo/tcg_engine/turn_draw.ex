defmodule Prizmo.TcgEngine.TurnDraw do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.PlayerStore

  def draw_one_for_turn(game_id, player_id) do
    with {:ok, player} <- PlayerStore.get_player(game_id, player_id),
         {:ok, [card | _rest]} <- CardStore.deck_cards_for_player(player.id, 1) do
      update(card, :draw_to_hand, %{position: CardStore.next_hand_position(game_id, player_id)})
    else
      {:ok, []} -> {:error, :cannot_draw_from_empty_deck}
      {:error, reason} -> {:error, reason}
    end
  end
end
