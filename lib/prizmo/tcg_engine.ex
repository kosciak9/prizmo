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
      rpc_action :get_tcg_engine_game_state, :get_state
      rpc_action :start_tcg_engine_setup, :start_setup_command
      rpc_action :draw_tcg_engine_opening_hand, :draw_opening_hand_command
      rpc_action :choose_tcg_engine_active_from_hand, :choose_active_from_hand_command
      rpc_action :choose_tcg_engine_setup_bench_from_hand, :choose_setup_bench_from_hand_command
      rpc_action :place_tcg_engine_prizes, :place_prizes_command
      rpc_action :complete_tcg_engine_setup, :complete_setup_command
      rpc_action :start_next_tcg_engine_turn, :start_next_turn_command
      rpc_action :draw_tcg_engine_card_for_turn, :draw_for_turn_command
      rpc_action :skip_tcg_engine_draw_for_turn, :skip_draw_for_turn_command
      rpc_action :open_tcg_engine_action_window, :open_action_window_command
      rpc_action :play_tcg_engine_card, :play_card_command
      rpc_action :play_tcg_engine_basic_to_bench, :play_basic_to_bench_command
      rpc_action :attach_tcg_engine_energy, :attach_energy_command
      rpc_action :choose_tcg_engine_prompt, :choose_prompt_command
    end
  end

  resources do
    resource Prizmo.TcgEngine.CardInstance

    resource Game do
      define :get_game_by_id, action: :read, get_by: [:id]
      define :list_supported_decks, action: :list_supported_decks
      define :create_supported_game, action: :create_from_supported_decks, args: [:players]
      define :get_game_state, action: :get_state, args: [:game_id, :viewer_player_id]
      define :start_setup_game, action: :start_setup_command, args: [:game_id]
      define :draw_opening_hand_for_game, action: :draw_opening_hand_command, args: [:game_id]

      define :choose_active_from_hand_for_game,
        action: :choose_active_from_hand_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :choose_setup_bench_from_hand_for_game,
        action: :choose_setup_bench_from_hand_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :place_prizes_for_game, action: :place_prizes_command, args: [:game_id]
      define :complete_setup_for_game, action: :complete_setup_command, args: [:game_id]
      define :start_next_turn_for_game, action: :start_next_turn_command, args: [:game_id]
      define :draw_for_turn_for_game, action: :draw_for_turn_command, args: [:game_id, :player_id]

      define :skip_draw_for_turn_for_game,
        action: :skip_draw_for_turn_command,
        args: [:game_id, :player_id]

      define :open_action_window_for_game, action: :open_action_window_command, args: [:game_id]

      define :play_card_for_game,
        action: :play_card_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :play_basic_to_bench_for_game,
        action: :play_basic_to_bench_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :attach_energy_for_game,
        action: :attach_energy_command,
        args: [:game_id, :player_id, :energy_card_instance_id, :target_card_instance_id]

      define :choose_prompt_for_game,
        action: :choose_prompt_command,
        args: [:game_id, :player_id, :prompt_id, :selected_card_instance_ids]
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
