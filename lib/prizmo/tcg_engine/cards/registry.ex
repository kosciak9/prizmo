defmodule Prizmo.TcgEngine.Cards.Registry do
  @moduledoc false

  alias Prizmo.TcgEngine.Cards.CardDefinition
  alias Prizmo.TcgEngine.Cards.Cost
  alias Prizmo.TcgEngine.Cards.Effect

  @crispin %CardDefinition{
    id: "SCR-133",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_basic_energy_split_hand_attach_to_pokemon,
        type: :search_basic_energy_split_hand_attach,
        params: %{min_count: 1, max_count: 3, shuffle_after: true}
      }
    ]
  }

  @rare_candy %CardDefinition{
    id: "MEG-125",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :rare_candy_evolve_basic_to_stage_2,
        type: :rare_candy_evolve,
        params: %{count: 2}
      }
    ]
  }

  @dawn %CardDefinition{
    id: "PFL-087",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_basic_stage_1_stage_2_pokemon,
        type: :search_deck,
        params: %{
          filter: %{
            any: [
              %{kind: :pokemon, stage: :basic},
              %{kind: :pokemon, stage: :stage_1},
              %{kind: :pokemon, stage: :stage_2}
            ]
          },
          required_groups: [
            %{filter: %{kind: :pokemon, stage: :basic}, count: 1},
            %{filter: %{kind: :pokemon, stage: :stage_1}, count: 1},
            %{filter: %{kind: :pokemon, stage: :stage_2}, count: 1}
          ],
          count: 3,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @hilda %CardDefinition{
    id: "WHT-084",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_evolution_pokemon_and_energy,
        type: :search_deck,
        params: %{
          filter: %{
            any: [
              %{kind: :pokemon, stages: [:stage_1, :stage_2]},
              %{kind: :energy}
            ]
          },
          required_groups: [
            %{filter: %{kind: :pokemon, stages: [:stage_1, :stage_2]}, count: 1},
            %{filter: %{kind: :energy}, count: 1}
          ],
          count: 2,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

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

  @enhanced_hammer %CardDefinition{
    id: "TWM-148",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :discard_opponent_special_energy,
        type: :discard_opponent_special_energy,
        params: %{count: 1}
      }
    ]
  }

  @energy_switch %CardDefinition{
    id: "MEG-115",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :move_basic_energy_between_own_pokemon,
        type: :move_basic_energy_between_own_pokemon,
        params: %{count: 2}
      }
    ]
  }

  @night_stretcher %CardDefinition{
    id: "ASC-196",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :recover_pokemon_or_basic_energy_from_discard,
        type: :recover_discard_to_hand,
        params: %{
          filter: %{any: [%{kind: :pokemon}, %{kind: :energy, energy_type: :basic}]},
          count: 1,
          destination: :hand
        }
      }
    ]
  }

  @lanas_aid %CardDefinition{
    id: "TWM-155",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :recover_non_rule_box_pokemon_or_basic_energy_from_discard,
        type: :recover_discard_to_hand,
        params: %{
          filter: %{
            any: [
              %{kind: :pokemon, rule_box?: false},
              %{kind: :energy, energy_type: :basic}
            ]
          },
          min_count: 1,
          max_count: 3,
          destination: :hand
        }
      }
    ]
  }

  @pokegear_3_0 %CardDefinition{
    id: "SVI-186",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_top_7_for_supporter_to_hand,
        type: :search_top_deck,
        params: %{
          look_count: 7,
          filter: %{kind: :trainer, trainer_type: :supporter},
          min_count: 0,
          max_count: 1,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @bug_catching_set %CardDefinition{
    id: "TWM-143",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_top_7_for_grass_pokemon_or_basic_grass_energy,
        type: :search_top_deck,
        params: %{
          look_count: 7,
          filter: %{
            any: [
              %{kind: :pokemon, type: :grass},
              %{kind: :energy, energy_type: :basic, provides: :grass}
            ]
          },
          min_count: 0,
          max_count: 2,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
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
    @bug_catching_set.id => @bug_catching_set,
    @buddy_buddy_poffin.id => @buddy_buddy_poffin,
    @crispin.id => @crispin,
    @dawn.id => @dawn,
    @enhanced_hammer.id => @enhanced_hammer,
    @energy_switch.id => @energy_switch,
    @hilda.id => @hilda,
    @judge.id => @judge,
    @lanas_aid.id => @lanas_aid,
    @lillies_determination.id => @lillies_determination,
    @night_stretcher.id => @night_stretcher,
    @poke_pad.id => @poke_pad,
    @pokegear_3_0.id => @pokegear_3_0,
    @rare_candy.id => @rare_candy,
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
