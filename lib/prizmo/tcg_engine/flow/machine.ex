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
    }
  }

  @always_transitions %{
    setup_dealing_opening_hands: [
      %{
        guard: :opening_hands_not_dealt?,
        action: :deal_opening_hands,
        target: :setup_choosing_opening_active
      }
    ]
  }

  def public_transition(event), do: Map.fetch(@public_transitions, event)
  def always_transitions(state), do: Map.get(@always_transitions, state, [])
end
