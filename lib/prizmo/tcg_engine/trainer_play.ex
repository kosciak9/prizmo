defmodule Prizmo.TcgEngine.TrainerPlay do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer

  def discard_trainer_card(
        %Game{} = game,
        %GamePlayer{} = player,
        %CardInstance{} = card,
        metadata
      ) do
    with {:ok, position} <- CardStore.next_discard_position(game.id, player.player_id),
         {:ok, discarded_card} <- update(card, :discard, %{position: position}) do
      with {:ok, _player} <- mark_trainer_flags(player, metadata) do
        {:ok, discarded_card}
      end
    end
  end

  def mark_trainer_flags(%GamePlayer{} = player, metadata) do
    with {:ok, player} <- maybe_mark_supporter_played(player, metadata) do
      maybe_mark_ace_spec_played(player, metadata)
    end
  end

  defp maybe_mark_supporter_played(%GamePlayer{} = player, %{trainer_type: :supporter}) do
    update(player, :mark_supporter_played, %{})
  end

  defp maybe_mark_supporter_played(%GamePlayer{} = player, _metadata), do: {:ok, player}

  defp maybe_mark_ace_spec_played(%GamePlayer{} = player, %{ace_spec?: true}) do
    update(player, :mark_ace_spec_played, %{})
  end

  defp maybe_mark_ace_spec_played(%GamePlayer{} = player, _metadata), do: {:ok, player}
end
