defmodule Prizmo.Tcg.Sim.StateMachines.CardLifecycle do
  @moduledoc """
  Lifecycle for a physical card instance.
  """

  alias Prizmo.Tcg.Sim.StateMachine

  @transitions %{
    in_deck: %{
      draw: :in_hand,
      prize: :prized,
      discard_from_deck: :discarded,
      search_to_hand: :in_hand,
      put_in_play: :in_play_basic
    },
    in_hand: %{
      play_basic: :in_play_basic,
      evolve: :in_play_evolved,
      attach: :attached,
      discard: :discarded,
      play_stadium: :in_stadium,
      shuffle_into_deck: :in_deck
    },
    in_play_basic: %{
      evolve: :in_play_evolved,
      attach_to: :attached,
      knock_out: :discarded,
      return_to_hand: :in_hand,
      shuffle_into_deck: :in_deck
    },
    in_play_evolved: %{
      attach_to: :attached,
      devolve: :in_play_basic,
      knock_out: :discarded,
      return_to_hand: :in_hand,
      shuffle_into_deck: :in_deck
    },
    attached: %{discard: :discarded, return_to_hand: :in_hand, shuffle_into_deck: :in_deck},
    in_stadium: %{discard: :discarded},
    discarded: %{
      attach: :attached,
      recover_to_hand: :in_hand,
      shuffle_into_deck: :in_deck,
      lost_zone: :lost_zone
    },
    prized: %{take_prize: :in_hand},
    lost_zone: %{}
  }

  @spec transition(atom(), atom()) ::
          {:ok, atom()} | {:error, Prizmo.Tcg.Sim.IllegalTransition.t()}
  def transition(state, event),
    do: StateMachine.transition(__MODULE__, @transitions, state, event)

  def transitions, do: @transitions
end
