defmodule Prizmo.Tcg.Sim.StateMachines.ZoneMovement do
  @moduledoc """
  Validates legal source/target zone movement for card instances.
  """

  alias Prizmo.Tcg.Sim.IllegalTransition

  @allowed %{
    deck: [:hand, :prizes, :discard, :bench, :active],
    hand: [:deck, :discard, :bench, :active, :attached, :stadium],
    prizes: [:hand],
    discard: [:hand, :deck, :lost_zone, :attached],
    active: [:discard, :hand, :deck, :bench],
    bench: [:discard, :hand, :deck, :active],
    attached: [:discard, :hand, :deck],
    stadium: [:discard],
    lost_zone: []
  }

  @spec transition(atom(), atom()) :: {:ok, atom()} | {:error, IllegalTransition.t()}
  def transition(from, to) do
    if to in Map.get(@allowed, from, []) do
      {:ok, to}
    else
      {:error, IllegalTransition.new(__MODULE__, from, to, Map.get(@allowed, from, []))}
    end
  end

  def allowed, do: @allowed
end
