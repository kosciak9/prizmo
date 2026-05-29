defmodule Prizmo.TcgEngine do
  @moduledoc """
  Persisted Ash-backed mechanics for the Pokémon TCG simulator.
  """

  use Ash.Domain, otp_app: :prizmo, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Prizmo.TcgEngine.CardInstance

    resource Prizmo.TcgEngine.Game do
      define :get_game_by_id, action: :read, get_by: [:id]
    end

    resource Prizmo.TcgEngine.GameEvent
    resource Prizmo.TcgEngine.GamePlayer
    resource Prizmo.TcgEngine.GameSnapshot
    resource Prizmo.TcgEngine.PendingEffect
    resource Prizmo.TcgEngine.Prompt
    resource Prizmo.TcgEngine.Setup
    resource Prizmo.TcgEngine.Turn
  end
end
