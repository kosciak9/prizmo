defmodule Prizmo.TcgEngine.Cards.Registry do
  @moduledoc false

  alias Prizmo.TcgEngine.Cards.CardDefinition
  alias Prizmo.TcgEngine.Cards.Cost
  alias Prizmo.TcgEngine.Cards.Effect

  @judge %CardDefinition{
    id: "POR-076",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :shuffle_each_player_hand_into_deck_then_draw,
        type: :shuffle_each_player_hand_into_deck_then_draw,
        params: %{draw_count: 4}
      }
    ]
  }

  @lillies_determination %CardDefinition{
    id: "MEG-119",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :shuffle_hand_into_deck_then_draw,
        type: :shuffle_hand_into_deck_then_draw,
        params: %{draw_count: 6, full_prize_count: 6, full_prize_draw_count: 8}
      }
    ]
  }

  @boss_orders %CardDefinition{
    id: "MEG-114",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :switch_opponent_bench_to_active,
        type: :switch_opponent_bench_to_active,
        params: %{count: 1}
      }
    ]
  }

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

  @buddy_buddy_poffin %CardDefinition{
    id: "TEF-144",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_basic_pokemon_to_bench,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon, stage: :basic, max_hp: 70},
          min_count: 1,
          max_count: 2,
          destination: :bench,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @poke_pad %CardDefinition{
    id: "POR-081",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_non_rule_box_pokemon,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon, rule_box?: false},
          count: 1,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @cards %{
    @boss_orders.id => @boss_orders,
    @buddy_buddy_poffin.id => @buddy_buddy_poffin,
    @judge.id => @judge,
    @lillies_determination.id => @lillies_determination,
    @poke_pad.id => @poke_pad,
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
