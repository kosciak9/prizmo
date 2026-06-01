defmodule Prizmo.TcgEngine.Flow.Machine do
  @moduledoc false

  @public_transitions %{
    call_coin_toss: %{
      from: :pregame_awaiting_coin_toss,
      action: :record_coin_toss,
      target: :pregame_awaiting_starting_player_choice
    },
    choose_starting_player: %{
      from: :pregame_awaiting_starting_player_choice,
      action: :choose_starting_player,
      target: :setup_dealing_opening_hands
    },
    choose_setup_active: %{
      from: :setup_choosing_opening_active,
      action: :choose_setup_active,
      target: :setup_choosing_opening_active
    },
    mulligan_opening_hand: %{
      from: :setup_choosing_opening_active,
      action: :mulligan_opening_hand,
      target: :setup_choosing_opening_active
    },
    choose_setup_bench: %{
      from: :setup_choosing_opening_bench,
      action: :choose_setup_bench,
      target: :setup_choosing_opening_bench
    },
    draw_mulligan_bonus: %{
      from: :setup_choosing_opening_bench,
      action: :draw_mulligan_bonus,
      target: :setup_choosing_opening_bench
    },
    finish_setup_choices: %{
      from: :setup_choosing_opening_bench,
      action: :finish_setup_choices,
      target: :setup_choosing_opening_bench
    },
    pass: %{
      from: :turn_action_window,
      action: :pass_turn,
      target: :turn_ending_turn
    },
    declare_attack: %{
      from: :turn_action_window,
      action: :declare_attack,
      target: :turn_attack_declared
    }
  }

  @always_transitions %{
    setup_dealing_opening_hands: [
      %{
        guard: :opening_hands_not_dealt?,
        action: :deal_opening_hands,
        target: :setup_choosing_opening_active
      }
    ],
    setup_choosing_opening_active: [
      %{
        guard: :all_players_have_active?,
        action: :open_setup_bench_choices,
        target: :setup_choosing_opening_bench
      }
    ],
    setup_choosing_opening_bench: [
      %{
        guard: :all_players_setup_ready?,
        action: :place_setup_prizes,
        target: :setup_completing_setup
      }
    ],
    setup_completing_setup: [
      %{
        guard: :setup_prizes_complete?,
        action: :complete_setup,
        target: :turn_starting_turn
      }
    ],
    turn_starting_turn: [
      %{
        guard: :can_start_turn?,
        action: :start_turn,
        target: :turn_drawing_for_turn
      }
    ],
    turn_drawing_for_turn: [
      %{
        guard: :can_draw_for_turn?,
        action: :draw_for_turn,
        target: :turn_opening_action_window
      }
    ],
    turn_opening_action_window: [
      %{
        guard: :can_open_action_window?,
        action: :open_action_window,
        target: :turn_action_window
      }
    ],
    turn_ending_turn: [
      %{
        guard: :can_end_turn?,
        action: :end_turn,
        target: :turn_starting_turn
      }
    ],
    turn_attack_declared: [
      %{
        guard: :can_resolve_declared_attack?,
        action: :resolve_declared_attack,
        target: :turn_attack_resolving
      }
    ],
    turn_attack_resolving: [
      %{
        guard: :can_finish_attack?,
        action: :finish_attack,
        target: :turn_starting_turn
      }
    ]
  }

  def public_transition(event), do: Map.fetch(@public_transitions, event)
  def always_transitions(state), do: Map.get(@always_transitions, state, [])
end
