defmodule Prizmo.TcgEngine do
  @moduledoc """
  Persisted Ash-backed mechanics for the Pokémon TCG simulator.
  """

  use Ash.Domain, otp_app: :prizmo, extensions: [AshAdmin.Domain, AshTypescript.Rpc]

  alias Prizmo.TcgEngine.Game

  admin do
    show? true
  end

  typescript_rpc do
    resource Game do
      rpc_action :list_supported_tcg_decks, :list_supported_decks
      rpc_action :create_tcg_engine_game, :create_from_supported_decks
      rpc_action :start_tcg_engine_setup, :start_setup_command
    end
  end

  resources do
    resource Prizmo.TcgEngine.CardInstance

    resource Game do
      define :get_game_by_id, action: :read, get_by: [:id]
      define :list_supported_decks, action: :list_supported_decks
      define :create_supported_game, action: :create_from_supported_decks, args: [:players]
      define :start_setup_game, action: :start_setup_command, args: [:game_id]
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
