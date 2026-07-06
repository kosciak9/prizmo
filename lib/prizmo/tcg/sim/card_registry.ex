defmodule Prizmo.Tcg.Sim.CardRegistry do
  @moduledoc """
  Compatibility registry facade for the first simulator slice.

  Static card facts are loaded from the committed TCGdex cache. The local table
  below is now treated as an authored behavior overlay plus temporary migration
  shims for engine fields that the cache cannot yet express directly.

  Unsupported cards and unsupported cached attack text fail loudly instead of
  being approximated.
  """

  alias Prizmo.Tcg.Cards.Metadata

  @energy_name_types %{
    "Colorless" => :colorless,
    "Darkness" => :darkness,
    "Dragon" => :dragon,
    "Fairy" => :fairy,
    "Fighting" => :fighting,
    "Fire" => :fire,
    "Grass" => :grass,
    "Lightning" => :lightning,
    "Metal" => :metal,
    "Psychic" => :psychic,
    "Water" => :water
  }

  @cards %{
    "DRI-010" => %{
      abilities: %{
        flower_curtain: %{
          effect: %{type: :prevent_attack_damage_to_non_rule_box_bench}
        }
      },
      attacks: %{
        smash_kick: %{effect: nil}
      }
    },
    "DRI-019" => %{
      attacks: %{
        take_down: %{effect: %{type: :self_damage, damage: 10}}
      }
    },
    "DRI-020" => %{
      evolves_from: "DRI-019",
      abilities: %{
        charging_up: %{effect: %{type: :attach_basic_energy_from_discard_to_self}}
      },
      attacks: %{
        rocket_rush: %{
          damage: 0,
          effect: %{type: :damage_per_own_team_rocket_pokemon_in_play, damage_per_pokemon: 30}
        }
      }
    },
    "DRI-040" => %{
      attacks: %{
        collect: %{effect: %{type: :draw_after_attack, count: 1}},
        combustion: %{effect: nil}
      }
    },
    "DRI-041" => %{
      evolves_from: "DRI-040",
      attacks: %{
        combustion: %{effect: nil},
        double_kick: %{
          damage: 0,
          effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: 40}
        }
      }
    },
    "DRI-051" => %{
      abilities: %{
        repelling_veil: %{effect: %{type: :prevent_attack_effects_to_basic_team_rocket_pokemon}}
      },
      attacks: %{
        dark_frost: %{
          damage: 60,
          effect: %{type: :bonus_damage_if_attacker_has_team_rocket_energy, bonus_damage: 60}
        }
      }
    },
    "DRI-081" => %{
      abilities: %{
        power_saver: %{
          effect: %{type: :cannot_attack_unless_own_team_rocket_pokemon_in_play, count: 4}
        }
      },
      attacks: %{
        erasure_ball: %{
          effect: %{
            type: :discard_energy_from_own_bench_for_bonus_damage,
            max_discards: 2,
            bonus_damage: 60
          }
        }
      }
    },
    "DRI-087" => %{
      attacks: %{
        gemstone_mimicry: %{effect: %{type: :copy_opponent_active_tera_pokemon_attack}}
      }
    },
    "TWM-014" => %{
      attacks: %{
        smash_kick: %{effect: nil},
        branch_poke: %{effect: nil}
      }
    },
    "TWM-015" => %{
      evolves_from: "TWM-014",
      abilities: %{
        boom_boom_groove: %{
          effect: %{type: :search_deck_for_card_to_hand_if_active_has_festival_lead}
        }
      },
      attacks: %{
        beat: %{effect: nil}
      }
    },
    "TWM-017" => %{
      attacks: %{
        tumbling_attack: %{
          damage: 10,
          effect: %{type: :bonus_damage_on_coin_heads, bonus_damage: 20}
        }
      }
    },
    "TWM-018" => %{
      evolves_from: "TWM-017",
      abilities: %{
        festival_lead: %{effect: %{type: :may_attack_twice_if_festival_grounds_in_play}}
      },
      attacks: %{
        do_the_wave: %{
          damage: 0,
          effect: %{type: :damage_per_own_benched_pokemon, damage_per_pokemon: 20}
        }
      }
    },
    "TWM-025" => %{
      abilities: %{
        teal_dance: %{
          effect: %{type: :attach_basic_grass_energy_from_hand_to_self_then_draw, count: 1}
        }
      },
      attacks: %{
        myriad_leaf_shower: %{
          damage: 30,
          effect: %{type: :bonus_damage_per_energy_attached_to_both_active, bonus_damage: 30}
        }
      }
    },
    "TWM-039" => %{
      attacks: %{
        allure: %{damage: 0, effect: %{type: :draw_after_attack, count: 2}},
        ground_melter: %{
          damage: 60,
          effect: %{type: :bonus_damage_if_stadium_in_play_then_discard_stadium, bonus_damage: 60}
        }
      }
    },
    "PRE-035" => %{
      attacks: %{
        come_and_get_you: %{
          damage: 0,
          effect: %{type: :put_up_to_3_duskull_from_discard_to_bench}
        },
        mumble: %{effect: nil}
      }
    },
    "PRE-036" => %{
      evolves_from: "PRE-035",
      abilities: %{
        cursed_blast: %{
          effect: %{type: :damage_counters_to_opponent_pokemon_then_self_knock_out, counters: 5}
        }
      },
      attacks: %{
        will_o_wisp: %{effect: nil}
      }
    },
    "PRE-037" => %{
      evolves_from: "PRE-036",
      abilities: %{
        cursed_blast: %{
          effect: %{type: :damage_counters_to_opponent_pokemon_then_self_knock_out, counters: 13}
        }
      },
      attacks: %{
        shadow_bind: %{effect: %{type: :defending_pokemon_cannot_retreat_next_turn}}
      }
    },
    "TWM-044" => %{
      abilities: %{
        festival_lead: %{effect: %{type: :may_attack_twice_if_festival_grounds_in_play}}
      },
      attacks: %{
        whirlpool: %{effect: %{type: :discard_defending_energy_on_coin_heads}}
      }
    },
    "TWM-064" => %{
      attacks: %{
        sob: %{effect: %{type: :defending_pokemon_cannot_retreat_next_turn}},
        torrential_pump: %{
          effect: %{
            type: :shuffle_attached_energy_into_deck_then_damage_opponent_bench,
            energy_count: 3,
            bench_damage: 120
          }
        }
      }
    },
    "TWM-080" => %{
      abilities: %{
        teleporter: %{effect: %{type: :shuffle_self_and_attached_into_deck}}
      },
      attacks: %{
        beam: %{effect: nil}
      }
    },
    "TWM-126" => %{
      attacks: %{
        find_a_friend: %{damage: 0, effect: %{type: :search_pokemon_to_hand}},
        rolling_tackle: %{effect: nil}
      }
    },
    "SCR-012" => %{
      attacks: %{
        spray_fluid: %{effect: nil}
      }
    },
    "SCR-118" => %{
      abilities: %{
        fan_call: %{
          effect: %{
            type: :search_colorless_pokemon_with_100_hp_or_less_to_hand_on_first_turn,
            max_targets: 3
          }
        }
      },
      attacks: %{
        assault_landing: %{effect: %{type: :damage_only_if_stadium_in_play}}
      }
    },
    "SCR-131" => %{
      effect: %{type: :bench_limit_8_with_tera_in_play_else_discard_to_5}
    },
    "SCR-135" => %{
      effect: %{
        type: :attach_basic_energy_from_discard_to_benched_colorless_if_tera_in_play,
        max_targets: 2
      }
    },
    "PFL-083" => %{
      attacks: %{
        run_around: %{effect: %{type: :switch_self_with_bench}},
        kick: %{effect: nil}
      }
    },
    "PFL-084" => %{
      evolves_from: "PFL-083",
      attacks: %{
        gale_thrust: %{
          damage: 60,
          effect: %{
            type: :bonus_damage_if_moved_from_bench_to_active_this_turn,
            bonus_damage: 170
          }
        },
        spiky_hopper: %{effect: %{type: :damage_unaffected_by_effects_on_opponent_active}}
      }
    },
    "PFL-085" => %{
      effect: %{type: :prevent_damage_counters_to_bench_from_opponent_pokemon_effects}
    },
    "TWM-128" => %{
      attacks: %{
        petty_grudge: %{effect: nil},
        bite: %{effect: nil}
      }
    },
    "TWM-129" => %{
      name: "Drakloak",
      supertype: :pokemon,
      type: :dragon,
      stage: :stage_1,
      evolves_from: "TWM-128",
      hp: 90,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: nil,
      resistance: nil,
      abilities: %{
        recon_directive: %{
          name: "Recon Directive",
          effect: %{type: :top_two_choose_one_to_hand_other_to_bottom}
        }
      },
      attacks: %{
        dragon_headbutt: %{
          name: "Dragon Headbutt",
          cost: [:fire, :psychic],
          damage: 70,
          effect: nil
        }
      }
    },
    "TWM-130" => %{
      name: "Dragapult ex",
      supertype: :pokemon,
      type: :dragon,
      stage: :stage_2,
      evolves_from: "TWM-129",
      rule_box?: true,
      hp: 320,
      prize_count: 2,
      retreat_cost: [:colorless],
      weakness: nil,
      resistance: nil,
      attacks: %{
        jet_headbutt: %{name: "Jet Headbutt", cost: [:colorless], damage: 70, effect: nil},
        phantom_dive: %{
          name: "Phantom Dive",
          cost: [:fire, :psychic],
          damage: 200,
          effect: %{type: :opponent_bench_damage_counters, total_counters: 6}
        }
      }
    },
    "TWM-095" => %{
      name: "Munkidori",
      supertype: :pokemon,
      type: :psychic,
      stage: :basic,
      hp: 110,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :darkness, multiplier: 2},
      resistance: %{type: :fighting, value: -30},
      abilities: %{
        adrena_brain: %{
          name: "Adrena-Brain",
          effect: %{
            type: :move_damage_counters,
            max_counters: 3,
            requires_attached_type: :darkness
          }
        }
      },
      attacks: %{
        mind_bend: %{
          name: "Mind Bend",
          cost: [:psychic, :colorless],
          damage: 60,
          effect: %{type: :confuse_defender_active}
        }
      }
    },
    "ASC-016" => %{
      name: "Budew",
      supertype: :pokemon,
      type: :grass,
      stage: :basic,
      hp: 30,
      prize_count: 1,
      weakness: %{type: :fire, multiplier: 2},
      resistance: nil,
      attacks: %{
        itchy_pollen: %{
          name: "Itchy Pollen",
          cost: [],
          damage: 10,
          effect: %{type: :lock_opponent_items_next_turn}
        }
      }
    },
    "PFL-014" => %{
      name: "Moltres",
      supertype: :pokemon,
      type: :fire,
      stage: :basic,
      hp: 120,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :water, multiplier: 2},
      resistance: nil,
      attacks: %{
        fighting_wings: %{
          name: "Fighting Wings",
          cost: [:fire],
          damage: 20,
          effect: %{type: :bonus_damage_if_defender_pokemon_ex, bonus_damage: 90}
        }
      }
    },
    "ASC-142" => %{
      name: "Fezandipiti ex",
      supertype: :pokemon,
      type: :darkness,
      stage: :basic,
      rule_box?: true,
      hp: 210,
      prize_count: 2,
      retreat_cost: [:colorless],
      weakness: %{type: :fighting, multiplier: 2},
      resistance: nil,
      abilities: %{
        flip_the_script: %{
          name: "Flip the Script",
          effect: %{type: :draw_if_own_pokemon_knocked_out_last_turn, count: 3}
        }
      },
      attacks: %{
        cruel_arrow: %{
          name: "Cruel Arrow",
          cost: [:colorless, :colorless, :colorless],
          damage: 0,
          effect: %{type: :damage_one_opponent_pokemon, damage: 100}
        }
      }
    },
    "POR-062" => %{
      name: "Meowth ex",
      supertype: :pokemon,
      type: :colorless,
      stage: :basic,
      rule_box?: true,
      hp: 170,
      prize_count: 2,
      retreat_cost: [:colorless],
      weakness: %{type: :fighting, multiplier: 2},
      resistance: nil,
      abilities: %{
        last_ditch_catch: %{
          name: "Last-Ditch Catch",
          effect: %{type: :search_supporter_when_benched_from_hand, last_ditch?: true}
        }
      },
      attacks: %{
        tuck_tail: %{
          name: "Tuck Tail",
          cost: [:colorless, :colorless, :colorless],
          damage: 60,
          effect: %{type: :return_attacker_and_attached_to_hand}
        }
      }
    },
    "MEG-119" => %{name: "Lillie's Determination", supertype: :trainer, trainer_type: :supporter},
    "MEG-132" => %{
      effect: %{type: :heal_mega_evolution_pokemon_ex_then_return_attached_energy_to_hand}
    },
    "SCR-133" => %{name: "Crispin", supertype: :trainer, trainer_type: :supporter},
    "MEG-104" => %{
      abilities: %{
        run_errand: %{effect: %{type: :active_draw_once_per_turn, count: 2}}
      },
      attacks: %{
        rapid_fire_combo: %{
          damage: 200,
          effect: %{type: :bonus_damage_per_coin_heads_count, bonus_damage: 50}
        }
      }
    },
    "MEG-114" => %{name: "Boss's Orders", supertype: :trainer, trainer_type: :supporter},
    "POR-076" => %{name: "Judge", supertype: :trainer, trainer_type: :supporter},
    "PFL-087" => %{name: "Dawn", supertype: :trainer, trainer_type: :supporter},
    "POR-071" => %{name: "Crushing Hammer", supertype: :trainer, trainer_type: :item},
    "TEF-144" => %{name: "Buddy-Buddy Poffin", supertype: :trainer, trainer_type: :item},
    "POR-081" => %{name: "Poké Pad", supertype: :trainer, trainer_type: :item},
    "SVI-186" => %{
      name: "Pokégear 3.0",
      supertype: :trainer,
      trainer_type: :item,
      effect: %{type: :top_n_choose_supporter_to_hand, count: 7}
    },
    "SSP-170" => %{
      effect: %{type: :search_pokemon_ex_to_hand, max_targets: 3}
    },
    "TEF-145" => %{
      effect: %{type: :search_deck_for_cards_to_top, count: 2}
    },
    "TEF-161" => %{
      provides: [:colorless],
      effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon}
    },
    "MEG-115" => %{
      name: "Energy Switch",
      supertype: :trainer,
      trainer_type: :item,
      effect: %{type: :move_basic_energy_between_own_pokemon}
    },
    "MEG-131" => %{name: "Ultra Ball", supertype: :trainer, trainer_type: :item},
    "ASC-196" => %{name: "Night Stretcher", supertype: :trainer, trainer_type: :item},
    "TWM-165" => %{
      name: "Unfair Stamp",
      supertype: :trainer,
      trainer_type: :item,
      ace_spec?: true
    },
    "MEG-127" => %{name: "Risky Ruins", supertype: :trainer, trainer_type: :stadium},
    "DRI-180" => %{name: "Team Rocket's Watchtower", supertype: :trainer, trainer_type: :stadium},
    "MEE-001" => %{},
    "MEE-002" => %{},
    "MEE-003" => %{},
    "MEE-004" => %{},
    "MEE-005" => %{},
    "MEE-006" => %{},
    "MEE-007" => %{},
    "MEG-054" => %{
      name: "Abra",
      supertype: :pokemon,
      type: :psychic,
      stage: :basic,
      hp: 50,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :darkness, multiplier: 2},
      resistance: %{type: :fighting, value: -30},
      attacks: %{
        teleportation_attack: %{
          name: "Teleportation Attack",
          cost: [:psychic],
          damage: 10,
          effect: %{type: :switch_self_with_bench}
        }
      }
    },
    "MEG-055" => %{
      name: "Kadabra",
      supertype: :pokemon,
      stage: :stage_1,
      evolves_from: "MEG-054",
      hp: 80,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :darkness, multiplier: 2},
      resistance: %{type: :fighting, value: -30},
      abilities: %{
        psychic_draw: %{name: "Psychic Draw", effect: %{type: :evolution_draw, count: 2}}
      },
      attacks: %{
        super_psy_bolt: %{name: "Super Psy Bolt", cost: [:psychic], damage: 30, effect: nil}
      }
    },
    "MEG-056" => %{
      name: "Alakazam",
      supertype: :pokemon,
      stage: :stage_2,
      evolves_from: "MEG-055",
      hp: 140,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :darkness, multiplier: 2},
      resistance: %{type: :fighting, value: -30},
      abilities: %{
        psychic_draw: %{name: "Psychic Draw", effect: %{type: :evolution_draw, count: 3}}
      },
      attacks: %{
        powerful_hand: %{
          name: "Powerful Hand",
          cost: [:psychic],
          damage: 0,
          effect: %{type: :active_damage_counters_per_hand_card, counters_per_card: 2}
        }
      }
    },
    "JTG-024" => %{
      evolves_from: "DRI-041",
      abilities: %{
        seething_spirit: %{
          effect: %{type: :attach_basic_energy_from_discard_to_own_pokemon}
        }
      },
      attacks: %{
        smolder_sault: %{effect: %{type: :attacker_cannot_attack_next_turn}}
      }
    },
    "JTG-056" => %{
      abilities: %{
        fairy_zone: %{effect: %{type: :opponent_darkness_pokemon_weakness_becomes_psychic}}
      },
      attacks: %{
        full_moon_rondo: %{
          damage: 20,
          effect: %{type: :bonus_damage_per_benched_pokemon, bonus_damage: 20}
        }
      }
    },
    "JTG-120" => %{
      name: "Dunsparce",
      supertype: :pokemon,
      type: :colorless,
      stage: :basic,
      hp: 70,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :fighting, multiplier: 2},
      resistance: nil,
      attacks: %{
        trading_places: %{
          name: "Trading Places",
          cost: [:colorless],
          damage: 0,
          effect: %{type: :switch_self_with_bench}
        },
        ram: %{name: "Ram", cost: [:colorless, :colorless], damage: 20, effect: nil}
      }
    },
    "TEF-081" => %{
      abilities: %{
        cobalt_command: %{
          effect: %{
            type: :future_pokemon_attack_damage_bonus_to_opponent_active,
            bonus_damage: 20,
            excluded_card_id: "TEF-081"
          }
        }
      },
      attacks: %{
        twin_shotels: %{
          damage: 0,
          effect: %{
            type: :damage_two_opponent_pokemon_unaffected_by_weakness_resistance_or_effects,
            damage: 50,
            target_count: 2
          }
        }
      }
    },
    "TEF-123" => %{
      attacks: %{
        bellowing_thunder: %{
          damage: 0,
          effect: %{type: :damage_per_discarded_own_basic_energy, damage_per_energy: 70}
        },
        burst_roar: %{damage: 0, effect: %{type: :discard_hand_then_draw, count: 6}}
      }
    },
    "TEF-128" => %{
      attacks: %{
        gnaw: %{effect: nil},
        dig: %{
          effect: %{type: :prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads}
        }
      }
    },
    "TEF-129" => %{
      name: "Dudunsparce",
      supertype: :pokemon,
      type: :colorless,
      stage: :stage_1,
      evolves_from: "JTG-120",
      hp: 140,
      prize_count: 1,
      retreat_cost: [:colorless, :colorless, :colorless],
      weakness: %{type: :fighting, multiplier: 2},
      resistance: nil,
      abilities: %{
        run_away_draw: %{
          name: "Run Away Draw",
          effect: %{type: :draw_then_shuffle_self_into_deck, count: 3}
        }
      },
      attacks: %{
        land_crush: %{
          name: "Land Crush",
          cost: [:colorless, :colorless, :colorless],
          damage: 90,
          effect: nil
        }
      }
    },
    "TEF-023" => %{
      name: "Rellor",
      supertype: :pokemon,
      type: :grass,
      stage: :basic,
      hp: 50,
      prize_count: 1,
      weakness: %{type: :fire, multiplier: 2},
      resistance: nil,
      attacks: %{
        slight_intrusion: %{
          name: "Slight Intrusion",
          cost: [:colorless],
          damage: 30,
          effect: %{type: :self_damage, damage: 10}
        }
      }
    },
    "TEF-024" => %{
      name: "Rabsca",
      supertype: :pokemon,
      type: :grass,
      stage: :stage_1,
      evolves_from: "TEF-023",
      hp: 70,
      prize_count: 1,
      weakness: %{type: :fire, multiplier: 2},
      resistance: nil,
      abilities: %{
        spherical_shield: %{
          name: "Spherical Shield",
          effect: %{type: :prevent_attack_damage_and_effects_to_bench}
        }
      },
      attacks: %{
        psychic: %{
          name: "Psychic",
          damage: 10,
          effect: %{type: :bonus_damage_per_energy_attached_to_defender, bonus_damage: 30}
        }
      }
    },
    "TEF-025" => %{
      abilities: %{
        rapid_vernier: %{
          effect: %{type: :switch_self_with_active_when_benched_and_move_energy_to_self}
        }
      },
      attacks: %{
        prism_edge: %{effect: %{type: :attacker_cannot_attack_next_turn}}
      }
    },
    "SFA-040" => %{
      name: "Genesect",
      supertype: :pokemon,
      type: :metal,
      stage: :basic,
      hp: 110,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :fire, multiplier: 2},
      resistance: %{type: :grass, value: -30},
      abilities: %{
        ace_nullifier: %{
          name: "ACE Nullifier",
          effect: %{type: :opponent_cannot_play_ace_spec_if_tool_attached}
        }
      },
      attacks: %{
        magnetic_blast: %{
          name: "Magnetic Blast",
          cost: [:metal, :colorless, :colorless],
          damage: 100,
          effect: nil
        }
      }
    },
    "SFA-064" => %{
      effect: %{type: :opponent_discards_to_hand_size, target_hand_size: 3}
    },
    "ASC-039" => %{
      name: "Psyduck",
      supertype: :pokemon,
      type: :water,
      stage: :basic,
      hp: 70,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :lightning, multiplier: 2},
      resistance: nil,
      abilities: %{
        damp: %{
          name: "Damp",
          effect: %{type: :pokemon_lose_self_knock_out_abilities}
        }
      },
      attacks: %{
        ram: %{name: "Ram", cost: [:colorless, :colorless], damage: 20, effect: nil}
      }
    },
    "SSP-056" => %{
      abilities: %{
        snow_sink: %{effect: %{type: :discard_stadium_when_benched_from_hand}}
      },
      attacks: %{
        icicle_loop: %{effect: %{type: :return_attached_energy_to_hand}}
      }
    },
    "SSP-076" => %{
      abilities: %{
        skyliner: %{effect: %{type: :basic_pokemon_have_no_retreat_cost}}
      },
      attacks: %{
        eon_blade: %{effect: %{type: :attacker_cannot_attack_next_turn}}
      }
    },
    "SSP-087" => %{
      name: "Dedenne",
      supertype: :pokemon,
      type: :psychic,
      stage: :basic,
      hp: 70,
      prize_count: 1,
      retreat_cost: [:colorless],
      weakness: %{type: :metal, multiplier: 2},
      resistance: nil,
      attacks: %{
        electromagnetic_sonar: %{
          name: "Electromagnetic Sonar",
          cost: [:colorless],
          damage: 0,
          effect: %{type: :recover_trainer_from_discard_to_hand}
        },
        gnaw: %{name: "Gnaw", cost: [:psychic], damage: 30, effect: nil}
      }
    },
    "SSP-111" => %{
      attacks: %{
        coordinated_throwing: %{
          damage: 0,
          effect: %{type: :damage_per_own_basic_pokemon_in_play, damage_per_pokemon: 20}
        }
      }
    },
    "WHT-084" => %{name: "Hilda", supertype: :trainer, trainer_type: :supporter},
    "TWM-155" => %{name: "Lana's Aid", supertype: :trainer, trainer_type: :supporter},
    "MEG-125" => %{name: "Rare Candy", supertype: :trainer, trainer_type: :item},
    "TWM-148" => %{name: "Enhanced Hammer", supertype: :trainer, trainer_type: :item},
    "TWM-143" => %{
      name: "Bug Catching Set",
      supertype: :trainer,
      trainer_type: :item,
      effect: %{
        type: :top_n_choose_grass_pokemon_or_basic_grass_energy_to_hand,
        count: 7,
        max_targets: 2
      }
    },
    "TWM-149" => %{
      effect: %{type: :special_condition_immunity_for_pokemon_with_energy}
    },
    "DRI-168" => %{name: "Sacred Ash", supertype: :trainer, trainer_type: :item},
    "DRI-170" => %{
      effect: %{
        type: :shuffle_each_player_hand_into_deck_then_draw_if_team_rocket_knocked_out,
        player_draw: 5,
        opponent_draw: 3
      }
    },
    "DRI-171" => %{
      effect: %{
        type: :draw_until_hand_size_or_more_if_all_own_pokemon_are_team_rocket,
        hand_size: 5,
        team_rocket_hand_size: 8
      }
    },
    "DRI-173" => %{
      effect: %{type: :draw_after_playing_team_rocket_supporter, count: 2}
    },
    "DRI-174" => %{
      effect: %{
        type: :switch_active_team_rocket_with_benched_team_rocket_then_gust_opponent
      }
    },
    "DRI-177" => %{
      effect: %{type: :search_basic_team_rocket_pokemon_to_hand, max_targets: 3}
    },
    "DRI-178" => %{
      name: "Team Rocket's Transceiver",
      supertype: :trainer,
      trainer_type: :item,
      effect: %{type: :search_team_rocket_supporter_to_hand}
    },
    "TWM-154" => %{
      effect: %{
        type:
          :choose_switch_active_or_turn_bonus_attack_damage_to_opponent_active_pokemon_ex_or_v,
        bonus_damage: 30
      }
    },
    "JTG-143" => %{
      effect: %{
        type: :turn_bonus_attack_damage_to_opponent_active_pokemon_ex,
        bonus_damage: 40
      }
    },
    "TWM-150" => %{name: "Handheld Fan", supertype: :trainer, trainer_type: :tool},
    "TWM-153" => %{
      effect: %{type: :pokemon_tools_have_no_effect}
    },
    "TWM-158" => %{
      effect: %{type: :draw_cards_if_damaged_as_active_by_attack, count: 2}
    },
    "TWM-163" => %{
      effect: %{
        type: :discard_3_then_search_item_tool_supporter_stadium_to_hand,
        discard_count: 3,
        trainer_types: [:item, :tool, :supporter, :stadium]
      }
    },
    "SSP-169" => %{
      effect: %{type: :reduce_attack_cost_by_colorless_if_more_prizes_remaining, amount: 1}
    },
    "ASC-181" => %{name: "Air Balloon", supertype: :trainer, trainer_type: :tool},
    "WHT-080" => %{
      effect: %{
        type: :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
        bonus_damage: 30
      }
    },
    "MEG-117" => %{name: "Forest of Vitality", supertype: :trainer, trainer_type: :stadium},
    "PRE-021" => %{
      abilities: %{
        festival_lead: %{effect: %{type: :may_attack_twice_if_festival_grounds_in_play}}
      },
      attacks: %{
        rapid_draw: %{effect: %{type: :draw_after_attack, count: 2}}
      }
    },
    "POR-084" => %{
      effect: %{
        type: :attach_basic_energy_from_discard_to_stage2_if_more_prizes,
        max_targets: 2
      }
    },
    "POR-086" => %{
      provides: [:grass],
      effect: %{type: :grass_pokemon_hp_plus_20_energy}
    },
    "POR-088" => %{
      name: "Telepathic Psychic Energy",
      supertype: :energy,
      energy_type: :special,
      provides: [:psychic],
      effect: %{type: :bench_basic_psychic_from_deck_when_attached_to_psychic, max_targets: 2}
    },
    "SSP-191" => %{
      name: "Enriching Energy",
      supertype: :energy,
      energy_type: :special,
      provides: [:colorless],
      effect: %{type: :draw_when_attached_from_hand, count: 4}
    },
    "DRI-182" => %{
      provides: [:psychic, :darkness],
      effect: %{type: :team_rocket_energy_attachment_and_dual_provides}
    },
    "CRI-082" => %{
      effect: %{
        type: :opponent_hand_to_bottom_then_draw_if_any,
        draw_count: 3,
        requires_opponent_prize_count_at_most: 3
      }
    }
  }

  def fetch(card_id) do
    with {:ok, overlay} <- Map.fetch(@cards, card_id),
         {:ok, metadata} <- Metadata.fetch(card_id) do
      {:ok, metadata |> metadata_card() |> apply_behavior_overlay(overlay)}
    else
      :error -> {:error, {:unsupported_card, card_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch!(card_id) do
    case fetch(card_id) do
      {:ok, card} -> card
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  def basic_pokemon?(card_id) do
    match?({:ok, %{supertype: :pokemon, stage: :basic}}, fetch(card_id))
  end

  def fetch_attack(card_id, attack_id) do
    with {:ok, %{attacks: attacks}} <- fetch(card_id),
         {:ok, attack} <- Map.fetch(attacks, attack_id),
         :ok <- require_executable_attack(card_id, attack_id, attack) do
      {:ok, Map.put(attack, :id, attack_id)}
    else
      {:ok, _card_without_attacks} -> {:error, {:unsupported_attack, card_id, attack_id}}
      :error -> {:error, {:unsupported_attack, card_id, attack_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def supported_card_ids, do: @cards |> Map.keys() |> Enum.sort()

  defp metadata_card(%Metadata{} = metadata) do
    %{
      abilities: registry_abilities(metadata.abilities),
      ace_spec?: metadata.ace_spec?,
      attacks: registry_attacks(metadata.attacks),
      category: metadata.category,
      energy_type: registry_energy_type(metadata),
      evolves_from: metadata.evolves_from,
      evolves_from_name: metadata.evolves_from,
      hp: metadata.hp,
      id: metadata.id,
      image: metadata.image,
      legal: metadata.legal,
      name: metadata.name,
      raw_effect: metadata.raw_effect,
      regulation_mark: metadata.regulation_mark,
      resistance: first_resistance(metadata.resistances),
      resistances: metadata.resistances,
      retreat_cost: metadata.retreat_cost,
      retreat_count: metadata.retreat_count,
      rule_box?: metadata.rule_box?,
      rarity: metadata.rarity,
      set: metadata.set,
      stage: metadata.stage,
      suffix: metadata.suffix,
      supertype: metadata.category,
      tcgdex_energy_type: metadata.energy_type,
      tcgdex_id: metadata.tcgdex_id,
      trainer_type: metadata.trainer_type,
      type: primary_type(metadata),
      types: metadata.types,
      weakness: first_weakness(metadata.weaknesses),
      weaknesses: metadata.weaknesses
    }
  end

  defp apply_behavior_overlay(card, overlay) do
    card
    |> merge_attack_overlays(Map.get(overlay, :attacks, %{}))
    |> merge_ability_overlays(Map.get(overlay, :abilities, %{}))
    |> maybe_put_overlay(:effect, Map.get(overlay, :effect))
    |> maybe_put_overlay(:provides, Map.get(overlay, :provides, inferred_provides(card)))
    |> apply_metadata_gap_shims(overlay)
  end

  defp merge_attack_overlays(card, overlays) do
    attacks = merge_entry_overlays(card.attacks, overlays, &executable_attack_fields/2)
    %{card | attacks: attacks}
  end

  defp merge_ability_overlays(card, overlays) do
    abilities =
      merge_entry_overlays(card.abilities, overlays, fn _entry, overlay ->
        Map.take(overlay, [:effect])
      end)

    %{card | abilities: abilities}
  end

  defp merge_entry_overlays(entries, overlays, fields_fun) do
    Enum.reduce(overlays, entries, fn {id, overlay}, entries ->
      entry = Map.get(entries, id, %{name: Map.get(overlay, :name)})
      Map.put(entries, id, Map.merge(entry, fields_fun.(entry, overlay)))
    end)
  end

  defp executable_attack_fields(entry, overlay) do
    overlay
    |> Map.take([:effect])
    |> maybe_put_executable_damage(entry, overlay)
  end

  defp maybe_put_executable_damage(fields, %{damage: damage}, %{damage: executable_damage})
       when is_integer(damage) and not is_nil(executable_damage) do
    fields
  end

  defp maybe_put_executable_damage(fields, _entry, %{damage: executable_damage})
       when is_integer(executable_damage) do
    Map.put(fields, :damage, executable_damage)
  end

  defp maybe_put_executable_damage(fields, _entry, _overlay), do: fields

  # Temporary shims for cache gaps or incompatible static shapes required by
  # the current reducer. Keep these explicit until the engine no longer needs
  # Prizmo-ID evolution links or fallback weakness/resistance maps.
  defp apply_metadata_gap_shims(card, overlay) do
    card
    |> maybe_put_overlay(:evolves_from, Map.get(overlay, :evolves_from))
    |> maybe_put_gap(:weakness, Map.get(overlay, :weakness))
    |> maybe_put_gap(:resistance, Map.get(overlay, :resistance))
  end

  defp maybe_put_gap(card, field, value) do
    if metadata_gap?(Map.get(card, field)) do
      maybe_put_overlay(card, field, value)
    else
      card
    end
  end

  defp metadata_gap?(nil), do: true
  defp metadata_gap?([]), do: true
  defp metadata_gap?(_value), do: false

  defp maybe_put_overlay(card, _field, nil), do: card
  defp maybe_put_overlay(card, field, value), do: Map.put(card, field, value)

  defp registry_attacks(attacks) do
    Map.new(attacks, fn {id, attack} ->
      # sobelow_skip ["DOS.StringToAtom"] attack ids come from bounded compile-time card definitions.
      {String.to_atom(id),
       %{
         cost: attack.cost,
         damage: attack.damage,
         name: attack.name,
         raw_effect: attack.raw_effect
       }}
    end)
  end

  defp registry_abilities(abilities) do
    Map.new(abilities, fn {id, ability} ->
      # sobelow_skip ["DOS.StringToAtom"] ability ids come from bounded compile-time card definitions.
      {String.to_atom(id),
       %{
         name: ability.name,
         raw_effect: ability.raw_effect,
         type: ability.type
       }}
    end)
  end

  defp registry_energy_type(%Metadata{category: :energy, raw_effect: nil}), do: :basic
  defp registry_energy_type(%Metadata{category: :energy}), do: :special
  defp registry_energy_type(%Metadata{} = metadata), do: metadata.energy_type

  defp inferred_provides(%{supertype: :energy, energy_type: :basic, name: name}) do
    Enum.find_value(@energy_name_types, [], fn {label, type} ->
      if String.contains?(name, label), do: [type]
    end)
  end

  defp inferred_provides(_card), do: nil

  defp primary_type(%Metadata{types: [type | _types]}), do: type
  defp primary_type(%Metadata{}), do: nil

  defp first_weakness([%{type: type, value: value} | _weaknesses]) do
    %{type: type, multiplier: multiplier_value(value)}
  end

  defp first_weakness(_weaknesses), do: nil

  defp first_resistance([%{type: type, value: value} | _resistances]) do
    %{type: type, value: signed_value(value)}
  end

  defp first_resistance(_resistances), do: nil

  defp multiplier_value(value) when is_integer(value), do: value

  defp multiplier_value(value) do
    case Regex.run(~r/\d+/, to_string(value)) do
      [digits] -> String.to_integer(digits)
      _none -> 2
    end
  end

  defp signed_value(value) when is_integer(value), do: value

  defp signed_value(value) do
    case Regex.run(~r/-?\d+/, to_string(value)) do
      [digits] -> String.to_integer(digits)
      _none -> 0
    end
  end

  defp require_executable_attack(_card_id, _attack_id, %{effect: %{type: _type}}), do: :ok

  defp require_executable_attack(card_id, attack_id, %{raw_effect: raw_effect})
       when raw_effect not in [nil, ""] do
    {:error, {:missing_executable_attack_behavior, card_id, attack_id}}
  end

  defp require_executable_attack(_card_id, _attack_id, %{damage: damage}) when is_integer(damage),
    do: :ok

  defp require_executable_attack(card_id, attack_id, _attack),
    do: {:error, {:missing_executable_attack_behavior, card_id, attack_id}}
end
