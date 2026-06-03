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

  @team_rockets_archer %CardDefinition{
    id: "DRI-170",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :shuffle_each_player_hand_into_deck_then_draw_if_team_rocket_knocked_out,
        type: :shuffle_each_player_hand_into_deck_then_draw,
        params: %{
          player_draw_count: 5,
          opponent_draw_count: 3,
          requires_team_rocket_knockout_last_turn: true
        }
      }
    ]
  }

  @team_rockets_ariana %CardDefinition{
    id: "DRI-171",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :draw_until_hand_size_if_all_own_pokemon_are_team_rocket,
        type: :draw_until_hand_size,
        params: %{hand_size: 5, team_rocket_hand_size: 8}
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

  @wallys_compassion %CardDefinition{
    id: "MEG-132",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand,
        type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand,
        params: %{count: 1}
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

  @crushing_hammer %CardDefinition{
    id: "POR-071",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :discard_opponent_attached_energy_if_heads,
        type: :flip_coin_then_discard_opponent_attached_energy,
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

  @sacred_ash %CardDefinition{
    id: "DRI-168",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :shuffle_up_to_5_pokemon_from_discard_into_deck,
        type: :recover_discard_to_deck,
        params: %{
          filter: %{kind: :pokemon},
          min_count: 1,
          max_count: 5,
          shuffle_after: true
        }
      }
    ]
  }

  @secret_box %CardDefinition{
    id: "TWM-163",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    costs: [
      %Cost{
        key: :discard_three_from_hand,
        type: :discard_from_hand,
        params: %{count: 3}
      }
    ],
    effects: [
      %Effect{
        key: :search_deck_for_item_tool_supporter_stadium,
        type: :search_deck,
        params: %{
          filter: %{
            any: [
              %{kind: :trainer, trainer_type: :item},
              %{kind: :trainer, trainer_type: :tool},
              %{kind: :trainer, trainer_type: :supporter},
              %{kind: :trainer, trainer_type: :stadium}
            ]
          },
          max_groups: [
            %{filter: %{kind: :trainer, trainer_type: :item}, count: 1},
            %{filter: %{kind: :trainer, trainer_type: :tool}, count: 1},
            %{filter: %{kind: :trainer, trainer_type: :supporter}, count: 1},
            %{filter: %{kind: :trainer, trainer_type: :stadium}, count: 1}
          ],
          min_count: 0,
          max_count: 4,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @unfair_stamp %CardDefinition{
    id: "TWM-165",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :shuffle_each_player_hand_into_deck_then_draw,
        type: :shuffle_each_player_hand_into_deck_then_draw,
        params: %{
          player_draw_count: 5,
          opponent_draw_count: 2,
          requires_own_pokemon_knocked_out_last_turn: true
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

  @team_rockets_transceiver %CardDefinition{
    id: "DRI-178",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_team_rocket_supporter,
        type: :search_deck,
        params: %{
          filter: %{kind: :trainer, trainer_type: :supporter, name_contains: "Team Rocket"},
          count: 1,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @team_rockets_giovanni %CardDefinition{
    id: "DRI-174",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :switch_team_rocket_bench_and_opponent_bench_to_active,
        type: :switch_team_rocket_bench_and_opponent_bench_to_active,
        params: %{count: 2}
      }
    ]
  }

  @kieran %CardDefinition{
    id: "TWM-154",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :kieran_switch_or_damage_bonus,
        type: :kieran_switch_or_damage_bonus,
        params: %{bonus_damage: 30, min_count: 0, max_count: 1}
      }
    ]
  }

  @black_belts_training %CardDefinition{
    id: "JTG-143",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :turn_bonus_attack_damage_to_opponent_active_pokemon_ex,
        type: :turn_bonus_attack_damage_to_opponent_active_pokemon_ex,
        params: %{bonus_damage: 40}
      }
    ]
  }

  @team_rockets_proton %CardDefinition{
    id: "DRI-177",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    first_turn_supporter_allowed_when_going_first?: true,
    effects: [
      %Effect{
        key: :search_deck_for_basic_team_rocket_pokemon,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon, team_rocket?: true, stage: :basic},
          min_count: 0,
          max_count: 3,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @budew %CardDefinition{
    id: "ASC-016",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :itchy_pollen_lock_opponent_items_next_turn,
        type: :lock_opponent_items_next_turn,
        params: %{}
      }
    ]
  }

  @munkidori %CardDefinition{
    id: "TWM-095",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :adrena_brain_move_damage_counters,
        type: :move_damage_counters,
        params: %{max_counters: 3, requires_attached_type: :darkness}
      }
    ]
  }

  @dunsparce %CardDefinition{
    id: "JTG-120",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :trading_places_switch_self_with_bench,
        type: :switch_self_with_bench,
        params: %{}
      }
    ]
  }

  @raging_bolt_ex %CardDefinition{
    id: "TEF-123",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :bellowing_thunder_damage_per_discarded_energy,
        type: :damage_per_discarded_own_basic_energy,
        params: %{damage_per_energy: 70}
      },
      %Effect{
        key: :burst_roar_discard_hand_then_draw,
        type: :discard_hand_then_draw,
        params: %{count: 6}
      }
    ]
  }

  @tef_128_dunsparce %CardDefinition{
    id: "TEF-128",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :dig_prevent_damage_and_effects_next_turn_on_heads,
        type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads,
        params: %{}
      }
    ]
  }

  @tef_129_dudunsparce %CardDefinition{
    id: "TEF-129",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :run_away_draw,
        type: :draw_then_shuffle_self_into_deck,
        params: %{count: 3}
      }
    ]
  }

  @pfl_084_mega_lopunny_ex %CardDefinition{
    id: "PFL-084",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{key: :gale_thrust_or_spiky_hopper_attack, type: :plain_damage}
    ]
  }

  @glass_trumpet %CardDefinition{
    id: "SCR-135",
    kind: :trainer,
    trainer_type: :item,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :attach_basic_energy_from_discard_to_benched_colorless_if_tera,
        type: :attach_basic_energy_from_discard_to_benched_colorless_if_tera,
        params: %{max_targets: 2}
      }
    ]
  }

  @meowth_ex %CardDefinition{
    id: "POR-062",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :last_ditch_catch_search_supporter_when_benched_from_hand,
        type: :search_supporter_when_benched_from_hand,
        params: %{last_ditch?: true}
      },
      %Effect{
        key: :tuck_tail_return_attacker_and_attached_to_hand,
        type: :return_attacker_and_attached_to_hand,
        params: %{}
      }
    ]
  }

  @fezandipiti_ex %CardDefinition{
    id: "ASC-142",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :cruel_arrow_damage_any_opponent_pokemon,
        type: :damage_any_opponent_pokemon,
        params: %{amount: 20}
      }
    ]
  }

  @genesect %CardDefinition{
    id: "SFA-040",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :ace_nullifier_opponent_cannot_play_ace_spec_if_tool_attached,
        type: :opponent_cannot_play_ace_spec_if_tool_attached,
        params: %{}
      }
    ]
  }

  @teal_mask_ogerpon_ex %CardDefinition{
    id: "TWM-025",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :teal_dance_attach_grass_then_draw,
        type: :attach_basic_grass_energy_from_hand_to_self_then_draw,
        params: %{count: 1}
      }
    ]
  }

  @rellor %CardDefinition{
    id: "TEF-023",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :slight_intrusion_coin_flip_search_deck_on_heads_self_damage,
        type: :slight_intrusion_coin_flip_search_deck_on_heads_self_damage,
        params: %{self_damage: 10}
      }
    ]
  }

  @mega_lopunny_ex_twm %CardDefinition{
    id: "TWM-080",
    kind: :pokemon,
    play_window: :action_window,
    effects: [
      %Effect{key: :mega_lopunny_ex_attacks, type: :plain_damage}
    ]
  }

  @cyrano %CardDefinition{
    id: "SSP-170",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_pokemon_ex_to_hand,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon, rule_box: :ex},
          count: 3,
          destination: :hand,
          reveal: true,
          shuffle_after: true
        }
      }
    ]
  }

  @ciphermaniacs_codebreaking %CardDefinition{
    id: "TEF-145",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_deck_for_cards_to_top,
        type: :search_deck,
        params: %{count: 2, destination: :deck_top, reveal: false, shuffle_after: false}
      }
    ]
  }

  @fan_rotom %CardDefinition{
    id: "SCR-118",
    kind: :trainer,
    trainer_type: :supporter,
    play_window: :action_window,
    effects: [
      %Effect{
        key: :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn,
        type: :search_deck,
        params: %{
          filter: %{kind: :pokemon, type: :colorless, hp_max: 100},
          count: 3,
          destination: :hand,
          reveal: true,
          shuffle_after: true,
          first_turn_only: true
        }
      }
    ]
  }

  @cards %{
    @boss_orders.id => @boss_orders,
    @budew.id => @budew,
    @bug_catching_set.id => @bug_catching_set,
    @buddy_buddy_poffin.id => @buddy_buddy_poffin,
    @crushing_hammer.id => @crushing_hammer,
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
    @sacred_ash.id => @sacred_ash,
    @secret_box.id => @secret_box,
    @unfair_stamp.id => @unfair_stamp,
    @team_rockets_archer.id => @team_rockets_archer,
    @team_rockets_ariana.id => @team_rockets_ariana,
    @kieran.id => @kieran,
    @black_belts_training.id => @black_belts_training,
    @team_rockets_giovanni.id => @team_rockets_giovanni,
    @team_rockets_proton.id => @team_rockets_proton,
    @team_rockets_transceiver.id => @team_rockets_transceiver,
    @wallys_compassion.id => @wallys_compassion,
    @ultra_ball.id => @ultra_ball,
    @dunsparce.id => @dunsparce,
    @raging_bolt_ex.id => @raging_bolt_ex,
    @tef_128_dunsparce.id => @tef_128_dunsparce,
    @tef_129_dudunsparce.id => @tef_129_dudunsparce,
    @pfl_084_mega_lopunny_ex.id => @pfl_084_mega_lopunny_ex,
    @glass_trumpet.id => @glass_trumpet,
    @meowth_ex.id => @meowth_ex,
    @fezandipiti_ex.id => @fezandipiti_ex,
    @genesect.id => @genesect,
    @teal_mask_ogerpon_ex.id => @teal_mask_ogerpon_ex,
    @rellor.id => @rellor,
    @mega_lopunny_ex_twm.id => @mega_lopunny_ex_twm,
    @munkidori.id => @munkidori,
    @cyrano.id => @cyrano,
    @ciphermaniacs_codebreaking.id => @ciphermaniacs_codebreaking,
    @fan_rotom.id => @fan_rotom
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
