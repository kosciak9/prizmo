defmodule Prizmo.TcgEngine.Game.ActionCommands do
  @moduledoc false

  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.Mechanics

  actions do
    action :call_coin_toss_command, :struct do
      description "Call the setup coin toss through the game-flow machine."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :call, :atom do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.call_coin_toss(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.call
        )
      end
    end

    action :choose_starting_player_command, :struct do
      description "Choose who takes the first turn through the game-flow machine."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :chooser_player_id, :string do
        allow_nil? false
      end

      argument :starting_player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.choose_starting_player(
          input.arguments.game_id,
          input.arguments.chooser_player_id,
          input.arguments.starting_player_id
        )
      end
    end

    action :start_setup_command, :struct do
      description "Start setup for a persisted TCG engine game through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.start_setup(input.arguments.game_id)
      end
    end

    action :draw_opening_hand_command, :struct do
      description "Draw opening hands for a persisted TCG engine game through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.draw_opening_hand(input.arguments.game_id)
      end
    end

    action :choose_active_from_hand_command, :struct do
      description "Choose a player's setup Active Pokémon from hand through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.choose_active_from_hand(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id
        )
      end
    end

    action :mulligan_opening_hand_command, :struct do
      description "Shuffle a no-Basic opening hand into the deck and draw a replacement hand."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.mulligan_opening_hand(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :draw_mulligan_bonus_command, :struct do
      description "Draw optional setup bonus cards for an opponent opening-hand mulligan."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :count, :integer do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.draw_mulligan_bonus(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.count
        )
      end
    end

    action :choose_setup_bench_from_hand_command, :struct do
      description "Choose a player's setup Benched Pokémon from hand through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.choose_setup_bench_from_hand(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id
        )
      end
    end

    action :finish_setup_choices_command, :struct do
      description "Mark a player done with setup Bench choices through the game-flow machine."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.finish_setup_choices(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :place_prizes_command, :struct do
      description "Place setup Prize cards for a persisted TCG engine game through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.place_prizes(input.arguments.game_id)
      end
    end

    action :complete_setup_command, :struct do
      description "Complete setup for a persisted TCG engine game through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.complete_setup(input.arguments.game_id)
      end
    end

    action :start_next_turn_command, :struct do
      description "Start the next turn for a persisted TCG engine game through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.start_next_turn(input.arguments.game_id)
      end
    end

    action :draw_for_turn_command, :struct do
      description "Draw a card for the active player's current turn through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.draw_for_turn(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :skip_draw_for_turn_command, :struct do
      description "Skip drawing for the active player's current turn through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.skip_draw_for_turn(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :open_action_window_command, :struct do
      description "Open the active player's current turn action window through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.open_action_window(input.arguments.game_id)
      end
    end

    action :pass_turn_command, :struct do
      description "Pass from the action window and let the flow machine hand off the turn."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.pass_turn(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :undo_command, :struct do
      description "Restore the previous persisted game snapshot through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.undo(input.arguments.game_id)
      end
    end

    action :play_card_command, :struct do
      description "Play an engine-defined card from hand through the generic mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      argument :choices, :map do
        allow_nil? false
        default %{}
      end

      run fn input, _context ->
        Mechanics.play_card(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id,
          %{choices: input.arguments.choices}
        )
      end
    end

    action :play_stadium_command, :struct do
      description "Play a Stadium from hand through the generic mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.play_stadium(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id
        )
      end
    end

    action :use_team_rockets_factory_command, :struct do
      description "Use Team Rocket's Factory from the active Stadium zone through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_team_rockets_factory(
          input.arguments.game_id,
          input.arguments.player_id
        )
      end
    end

    action :use_munkidori_adrena_brain_command, :struct do
      description "Use Munkidori's Adrena-Brain Ability to move damage counters."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :from_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :damage_counters, :integer do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_munkidori_adrena_brain(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id,
          input.arguments.from_card_instance_id,
          input.arguments.target_card_instance_id,
          input.arguments.damage_counters
        )
      end
    end

    action :use_teal_mask_ogerpon_teal_dance_command, :struct do
      description "Use Teal Mask Ogerpon ex's Teal Dance Ability to attach Grass Energy and draw."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :energy_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_teal_mask_ogerpon_teal_dance(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id,
          input.arguments.energy_card_instance_id
        )
      end
    end

    action :use_blaziken_ex_seething_spirit_command, :struct do
      description "Use Blaziken ex's Seething Spirit Ability to attach Basic Energy from discard."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :energy_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_blaziken_ex_seething_spirit(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id,
          input.arguments.energy_card_instance_id,
          input.arguments.target_card_instance_id
        )
      end
    end

    action :use_cursed_blast_command, :struct do
      description "Use Dusclops or Dusknoir's Cursed Blast Ability to place damage counters, then Knock itself Out."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_cursed_blast(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id,
          input.arguments.target_card_instance_id
        )
      end
    end

    action :use_fezandipiti_flip_the_script_command, :struct do
      description "Use Fezandipiti ex's Flip the Script Ability to draw after an own KO last turn."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_fezandipiti_flip_the_script(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id
        )
      end
    end

    action :use_psychic_draw_command, :struct do
      description "Use Kadabra or Alakazam's Psychic Draw Ability after evolving from hand."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_psychic_draw(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id
        )
      end
    end

    action :use_fan_call_command, :struct do
      description "Use Fan Rotom's Fan Call Ability on first turn to search up to 3 Colorless Pokémon with 100 HP or less from deck to hand."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_fan_call(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id
        )
      end
    end

    action :use_drakloak_recon_directive_command, :struct do
      description "Use Drakloak's Recon Directive Ability to choose 1 of the top 2 deck cards."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :chosen_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_drakloak_recon_directive(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id,
          input.arguments.chosen_card_instance_id
        )
      end
    end

    action :use_dudunsparce_run_away_draw_command, :struct do
      description "Use Dudunsparce's Run Away Draw Ability to draw, then shuffle itself into the deck."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :source_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.use_dudunsparce_run_away_draw(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.source_card_instance_id
        )
      end
    end

    action :play_basic_to_bench_command, :struct do
      description "Play a Basic Pokémon from hand to the Bench through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.play_basic_to_bench(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.card_instance_id
        )
      end
    end

    action :evolve_from_hand_command, :struct do
      description "Evolve an in-play Pokémon using a valid evolution card from hand."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :evolution_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.evolve_from_hand(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.evolution_card_instance_id,
          input.arguments.target_card_instance_id
        )
      end
    end

    action :attach_energy_command, :struct do
      description "Attach one Energy from hand to a Pokémon in play through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :energy_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.attach_energy(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.energy_card_instance_id,
          input.arguments.target_card_instance_id
        )
      end
    end

    action :attach_tool_command, :struct do
      description "Attach one Pokémon Tool from hand to a Pokémon in play through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :tool_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :target_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.attach_tool(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.tool_card_instance_id,
          input.arguments.target_card_instance_id
        )
      end
    end

    action :end_turn_command, :struct do
      description "End the active player's current turn through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.end_turn(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :retreat_command, :struct do
      description "Retreat the active player's Active Pokémon to the Bench through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :bench_card_instance_id, :uuid do
        allow_nil? false
      end

      argument :energy_card_instance_ids, {:array, :uuid} do
        allow_nil? false
        default []
      end

      run fn input, _context ->
        Mechanics.retreat(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.bench_card_instance_id,
          input.arguments.energy_card_instance_ids
        )
      end
    end

    action :declare_attack_command, :struct do
      description "Declare an attack after validating the active Pokémon's attached Energy cost."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :attack_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.declare_attack(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.attack_id
        )
      end
    end

    action :resolve_declared_attack_command, :struct do
      description "Resolve the active player's declared attack through the mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :switch_bench_card_instance_id, :uuid do
        allow_nil? true
      end

      argument :discarded_energy_card_instance_ids, {:array, :uuid} do
        allow_nil? false
        default []
      end

      argument :returned_energy_card_instance_id, :uuid do
        allow_nil? true
      end

      argument :shuffled_energy_card_instance_ids, {:array, :uuid} do
        allow_nil? false
        default []
      end

      argument :bench_damage_target_card_instance_id, :uuid do
        allow_nil? true
      end

      argument :bench_damage_counter_allocations, :map do
        allow_nil? false
        default %{}
      end

      argument :damage_counter_move_selections, {:array, :map} do
        allow_nil? false
        default []
      end

      argument :coin_result, :string do
        allow_nil? true
      end

      argument :heads_count, :integer do
        allow_nil? true
      end

      argument :copied_attack_id, :string do
        allow_nil? true
      end

      argument :moved_opponent_energy_card_instance_id, :uuid do
        allow_nil? true
      end

      argument :moved_opponent_energy_target_card_instance_id, :uuid do
        allow_nil? true
      end

      argument :handheld_fan_attachment_id, :uuid do
        allow_nil? true
      end

      argument :handheld_fan_target_id, :uuid do
        allow_nil? true
      end

      run fn input, _context ->
        Mechanics.resolve_declared_attack(input.arguments.game_id, input.arguments.player_id, %{
          switch_bench_card_instance_id: Map.get(input.arguments, :switch_bench_card_instance_id),
          discarded_energy_card_instance_ids: input.arguments.discarded_energy_card_instance_ids,
          returned_energy_card_instance_id:
            Map.get(input.arguments, :returned_energy_card_instance_id),
          shuffled_energy_card_instance_ids: input.arguments.shuffled_energy_card_instance_ids,
          bench_damage_target_card_instance_id:
            Map.get(input.arguments, :bench_damage_target_card_instance_id),
          bench_damage_counter_allocations: input.arguments.bench_damage_counter_allocations,
          damage_counter_move_selections: input.arguments.damage_counter_move_selections,
          coin_result: Map.get(input.arguments, :coin_result),
          heads_count: Map.get(input.arguments, :heads_count),
          copied_attack_id: Map.get(input.arguments, :copied_attack_id),
          moved_opponent_energy_card_instance_id:
            Map.get(input.arguments, :moved_opponent_energy_card_instance_id),
          moved_opponent_energy_target_card_instance_id:
            Map.get(input.arguments, :moved_opponent_energy_target_card_instance_id),
          handheld_fan_attachment_id: Map.get(input.arguments, :handheld_fan_attachment_id),
          handheld_fan_target_id: Map.get(input.arguments, :handheld_fan_target_id)
        })
      end
    end

    action :finish_attack_command, :struct do
      description "Finish an already-resolved attack and end the active player's turn."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.finish_attack(input.arguments.game_id, input.arguments.player_id)
      end
    end

    action :choose_replacement_active_command, :struct do
      description "Choose a replacement Active Pokémon after a knockout leaves this player without one."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :bench_card_instance_id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.choose_replacement_active(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.bench_card_instance_id
        )
      end
    end

    action :choose_prompt_command, :struct do
      description "Resolve a select-cards prompt through the generic mechanics layer."

      constraints instance_of: Game

      argument :game_id, :uuid do
        allow_nil? false
      end

      argument :player_id, :string do
        allow_nil? false
      end

      argument :prompt_id, :uuid do
        allow_nil? false
      end

      argument :selected_card_instance_ids, {:array, :uuid} do
        allow_nil? false
      end

      run fn input, _context ->
        Mechanics.choose_prompt(
          input.arguments.game_id,
          input.arguments.player_id,
          input.arguments.prompt_id,
          input.arguments.selected_card_instance_ids
        )
      end
    end
  end
end
