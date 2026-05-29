defmodule Prizmo.TcgEngine.Cards.Registry do
  @moduledoc false

  alias Prizmo.TcgEngine.Cards.CardDefinition
  alias Prizmo.TcgEngine.Cards.Cost
  alias Prizmo.TcgEngine.Cards.Effect

  @ultra_ball %CardDefinition{
    id: "MEG-131",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    costs: [
      %Cost{
        key: :discard_two_from_hand,
        type: :discard_from_hand,
        params: %{count: 2}
      }
    ],
    effects: [
      %Effect{
        key: :search_deck_for_pokemon,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon},
          count: 1,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @cards %{
    @ultra_ball.id => @ultra_ball
  }

  def fetch(card_id) when is_binary(card_id) do
    case Map.fetch(@cards, card_id) do
      {:ok, definition} -> {:ok, definition}
      :error -> {:error, {:unsupported_engine_card, card_id}}
    end
  end

  def fetch!(card_id) do
    case fetch(card_id) do
      {:ok, definition} -> definition
      {:error, reason} -> raise ArgumentError, "unsupported engine card: #{inspect(reason)}"
    end
  end
end
