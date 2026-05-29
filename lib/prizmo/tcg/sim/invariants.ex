defmodule Prizmo.Tcg.Sim.Invariants do
  @moduledoc """
  State invariant checks for the simulator.

  These checks are intentionally strict because the simulator must be exact
  within supported scope and undo/redo must not duplicate or lose cards.
  """

  alias Prizmo.Tcg.Sim.GameState

  @spec validate_card_accounting(GameState.t()) :: :ok | {:error, term()}
  def validate_card_accounting(%GameState{} = state) do
    all_cards = cards_in_game(state)

    with :ok <- require_unique_instances(all_cards) do
      Enum.reduce_while(state.players, :ok, fn {player_id, player}, :ok ->
        cards = Enum.filter(all_cards, &(&1.owner == player_id))

        if player.expected_card_count && length(cards) != player.expected_card_count do
          {:halt,
           {:error, {:wrong_card_count, player_id, length(cards), player.expected_card_count}}}
        else
          {:cont, :ok}
        end
      end)
    end
  end

  def cards_for_player(player), do: cards_controlled_by_player(player)

  defp require_unique_instances(cards) do
    ids = Enum.map(cards, & &1.instance_id)

    if length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, :duplicate_card_instance}
    end
  end

  defp cards_in_game(state) do
    state.players
    |> Enum.flat_map(fn {_player_id, player} -> cards_controlled_by_player(player) end)
    |> Kernel.++(stadium_in_game(state))
  end

  defp cards_controlled_by_player(player) do
    [player.active]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&card_tree/1)
    |> Kernel.++(Enum.flat_map(player.bench, &card_tree/1))
    |> Kernel.++(Enum.flat_map(player.deck, &card_tree/1))
    |> Kernel.++(Enum.flat_map(player.hand, &card_tree/1))
    |> Kernel.++(Enum.flat_map(player.prizes, &card_tree/1))
    |> Kernel.++(Enum.flat_map(player.discard, &card_tree/1))
    |> Kernel.++(Enum.flat_map(player.lost_zone, &card_tree/1))
  end

  defp stadium_in_game(%{stadium: nil}), do: []
  defp stadium_in_game(%{stadium: stadium}), do: [stadium]

  defp card_tree(nil), do: []

  defp card_tree(card) do
    [card]
    |> Kernel.++(Enum.flat_map(card.attachments, &card_tree/1))
    |> Kernel.++(card_tree(card.tool))
    |> Kernel.++(Enum.flat_map(card.evolved_from, &card_tree/1))
  end
end
