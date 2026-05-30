defmodule Prizmo.TcgEngine.Game.ActionCommands do
  @moduledoc false

  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.Mechanics

  actions do
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

      argument :coin_result, :string do
        allow_nil? true
      end

      argument :heads_count, :integer do
        allow_nil? true
      end

      argument :copied_attack_id, :string do
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
          coin_result: Map.get(input.arguments, :coin_result),
          heads_count: Map.get(input.arguments, :heads_count),
          copied_attack_id: Map.get(input.arguments, :copied_attack_id)
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
