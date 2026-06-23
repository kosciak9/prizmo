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
      rpc_action :list_tcg_engine_games, :read
      rpc_action :list_supported_tcg_decks, :list_supported_decks
      rpc_action :get_supported_tcg_deck_blueprint, :get_supported_deck_blueprint
      rpc_action :create_tcg_engine_game, :create_from_supported_decks
      rpc_action :create_open_deck_tcg_engine_game, :create_from_decklists
      rpc_action :get_tcg_engine_game_state, :get_state
      rpc_action :call_tcg_engine_coin_toss, :call_coin_toss_command
      rpc_action :choose_tcg_engine_starting_player, :choose_starting_player_command
      rpc_action :start_tcg_engine_setup, :start_setup_command
      rpc_action :draw_tcg_engine_opening_hand, :draw_opening_hand_command
      rpc_action :choose_tcg_engine_active_from_hand, :choose_active_from_hand_command
      rpc_action :mulligan_tcg_engine_opening_hand, :mulligan_opening_hand_command
      rpc_action :draw_tcg_engine_mulligan_bonus, :draw_mulligan_bonus_command
      rpc_action :choose_tcg_engine_setup_bench_from_hand, :choose_setup_bench_from_hand_command
      rpc_action :finish_tcg_engine_setup_choices, :finish_setup_choices_command
      rpc_action :place_tcg_engine_prizes, :place_prizes_command
      rpc_action :complete_tcg_engine_setup, :complete_setup_command
      rpc_action :start_next_tcg_engine_turn, :start_next_turn_command
      rpc_action :draw_tcg_engine_card_for_turn, :draw_for_turn_command
      rpc_action :skip_tcg_engine_draw_for_turn, :skip_draw_for_turn_command
      rpc_action :open_tcg_engine_action_window, :open_action_window_command
      rpc_action :play_tcg_engine_card, :play_card_command
      rpc_action :play_tcg_engine_stadium, :play_stadium_command
      rpc_action :use_tcg_engine_team_rockets_factory, :use_team_rockets_factory_command
      rpc_action :use_tcg_engine_munkidori_adrena_brain, :use_munkidori_adrena_brain_command
      rpc_action :use_tcg_engine_teal_dance, :use_teal_mask_ogerpon_teal_dance_command
      rpc_action :use_tcg_engine_seething_spirit, :use_blaziken_ex_seething_spirit_command
      rpc_action :use_tcg_engine_cursed_blast, :use_cursed_blast_command
      rpc_action :use_tcg_engine_flip_the_script, :use_fezandipiti_flip_the_script_command
      rpc_action :use_tcg_engine_fan_call, :use_fan_rotom_fan_call_command
      rpc_action :use_tcg_engine_psychic_draw, :use_psychic_draw_command
      rpc_action :use_tcg_engine_recon_directive, :use_drakloak_recon_directive_command
      rpc_action :use_tcg_engine_run_away_draw, :use_dudunsparce_run_away_draw_command
      rpc_action :play_tcg_engine_basic_to_bench, :play_basic_to_bench_command
      rpc_action :evolve_tcg_engine_from_hand, :evolve_from_hand_command
      rpc_action :attach_tcg_engine_energy, :attach_energy_command
      rpc_action :attach_tcg_engine_tool, :attach_tool_command
      rpc_action :pass_tcg_engine_turn, :pass_turn_command
      rpc_action :undo_tcg_engine_game, :undo_command
      rpc_action :end_tcg_engine_turn, :end_turn_command
      rpc_action :retreat_tcg_engine_active, :retreat_command
      rpc_action :declare_tcg_engine_attack, :declare_attack_command
      rpc_action :resolve_tcg_engine_declared_attack, :resolve_declared_attack_command
      rpc_action :finish_tcg_engine_attack, :finish_attack_command
      rpc_action :choose_tcg_engine_replacement_active, :choose_replacement_active_command
      rpc_action :choose_tcg_engine_prompt, :choose_prompt_command
    end
  end

  resources do
    resource Prizmo.TcgEngine.CardInstance

    resource Game do
      define :get_game_by_id, action: :read, get_by: [:id]
      define :list_games, action: :read
      define :list_supported_decks, action: :list_supported_decks

      define :get_supported_deck_blueprint,
        action: :get_supported_deck_blueprint,
        args: [:deck_key]

      define :create_supported_game, action: :create_from_supported_decks, args: [:players]

      define :create_supported_game_with_seed,
        action: :create_from_supported_decks,
        args: [:players, :rng_seed]

      define :create_open_deck_game, action: :create_from_decklists, args: [:players]

      define :create_open_deck_game_with_seed,
        action: :create_from_decklists,
        args: [:players, :rng_seed]

      define :get_game_state, action: :get_state, args: [:game_id, :viewer_player_id]

      define :call_coin_toss_for_game,
        action: :call_coin_toss_command,
        args: [:game_id, :player_id, :call]

      define :choose_starting_player_for_game,
        action: :choose_starting_player_command,
        args: [:game_id, :chooser_player_id, :starting_player_id]

      define :start_setup_game, action: :start_setup_command, args: [:game_id]
      define :draw_opening_hand_for_game, action: :draw_opening_hand_command, args: [:game_id]

      define :choose_active_from_hand_for_game,
        action: :choose_active_from_hand_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :mulligan_opening_hand_for_game,
        action: :mulligan_opening_hand_command,
        args: [:game_id, :player_id]

      define :draw_mulligan_bonus_for_game,
        action: :draw_mulligan_bonus_command,
        args: [:game_id, :player_id, :count]

      define :choose_setup_bench_from_hand_for_game,
        action: :choose_setup_bench_from_hand_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :finish_setup_choices_for_game,
        action: :finish_setup_choices_command,
        args: [:game_id, :player_id]

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

      define :play_stadium_for_game,
        action: :play_stadium_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :use_team_rockets_factory_for_game,
        action: :use_team_rockets_factory_command,
        args: [:game_id, :player_id]

      define :use_munkidori_adrena_brain_for_game,
        action: :use_munkidori_adrena_brain_command,
        args: [
          :game_id,
          :player_id,
          :source_card_instance_id,
          :from_card_instance_id,
          :target_card_instance_id,
          :damage_counters
        ]

      define :use_teal_mask_ogerpon_teal_dance_for_game,
        action: :use_teal_mask_ogerpon_teal_dance_command,
        args: [:game_id, :player_id, :source_card_instance_id, :energy_card_instance_id]

      define :use_blaziken_ex_seething_spirit_for_game,
        action: :use_blaziken_ex_seething_spirit_command,
        args: [
          :game_id,
          :player_id,
          :source_card_instance_id,
          :energy_card_instance_id,
          :target_card_instance_id
        ]

      define :use_cursed_blast_for_game,
        action: :use_cursed_blast_command,
        args: [:game_id, :player_id, :source_card_instance_id, :target_card_instance_id]

      define :use_fezandipiti_flip_the_script_for_game,
        action: :use_fezandipiti_flip_the_script_command,
        args: [:game_id, :player_id, :source_card_instance_id]

      define :use_fan_rotom_fan_call_for_game,
        action: :use_fan_rotom_fan_call_command,
        args: [:game_id, :player_id, :source_card_instance_id]

      define :use_psychic_draw_for_game,
        action: :use_psychic_draw_command,
        args: [:game_id, :player_id, :source_card_instance_id]

      define :use_drakloak_recon_directive_for_game,
        action: :use_drakloak_recon_directive_command,
        args: [:game_id, :player_id, :source_card_instance_id, :chosen_card_instance_id]

      define :use_dudunsparce_run_away_draw_for_game,
        action: :use_dudunsparce_run_away_draw_command,
        args: [:game_id, :player_id, :source_card_instance_id]

      define :play_basic_to_bench_for_game,
        action: :play_basic_to_bench_command,
        args: [:game_id, :player_id, :card_instance_id]

      define :evolve_from_hand_for_game,
        action: :evolve_from_hand_command,
        args: [:game_id, :player_id, :evolution_card_instance_id, :target_card_instance_id]

      define :attach_energy_for_game,
        action: :attach_energy_command,
        args: [:game_id, :player_id, :energy_card_instance_id, :target_card_instance_id]

      define :attach_tool_for_game,
        action: :attach_tool_command,
        args: [:game_id, :player_id, :tool_card_instance_id, :target_card_instance_id]

      define :pass_turn_for_game,
        action: :pass_turn_command,
        args: [:game_id, :player_id]

      define :undo_for_game, action: :undo_command, args: [:game_id]

      define :end_turn_for_game,
        action: :end_turn_command,
        args: [:game_id, :player_id]

      define :retreat_active_for_game,
        action: :retreat_command,
        args: [:game_id, :player_id, :bench_card_instance_id, :energy_card_instance_ids]

      define :declare_attack_for_game,
        action: :declare_attack_command,
        args: [:game_id, :player_id, :attack_id]

      define :resolve_declared_attack_for_game,
        action: :resolve_declared_attack_command,
        args: [:game_id, :player_id]

      define :finish_attack_for_game,
        action: :finish_attack_command,
        args: [:game_id, :player_id]

      define :choose_replacement_active_for_game,
        action: :choose_replacement_active_command,
        args: [:game_id, :player_id, :bench_card_instance_id]

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
