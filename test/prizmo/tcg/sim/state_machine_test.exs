defmodule Prizmo.Tcg.Sim.StateMachineTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Sim.IllegalTransition
  alias Prizmo.Tcg.Sim.StateMachines.CardLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.GameLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.PromptLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.TurnLifecycle
  alias Prizmo.Tcg.Sim.StateMachines.ZoneMovement

  describe "game lifecycle" do
    test "allows setup to in-progress flow" do
      assert {:ok, :setup} = GameLifecycle.transition(:not_started, :start_setup)
      assert {:ok, :in_progress} = GameLifecycle.transition(:setup, :complete_setup)
    end

    test "rejects impossible game transitions with allowed events" do
      assert {:error,
              %IllegalTransition{
                state: :not_started,
                event: :complete_setup,
                allowed: [:start_setup]
              }} =
               GameLifecycle.transition(:not_started, :complete_setup)
    end
  end

  describe "turn lifecycle" do
    test "allows start, draw, action, and end turn flow" do
      assert {:ok, :start_turn} = TurnLifecycle.transition(:not_in_turn, :start_turn)
      assert {:ok, :draw_for_turn} = TurnLifecycle.transition(:start_turn, :draw_for_turn)
      assert {:ok, :action_window} = TurnLifecycle.transition(:draw_for_turn, :open_action_window)
      assert {:ok, :end_turn} = TurnLifecycle.transition(:action_window, :end_turn)
      assert {:ok, :not_in_turn} = TurnLifecycle.transition(:end_turn, :between_turns)
    end
  end

  describe "prompt lifecycle" do
    test "allows prompt suspension and completion" do
      assert {:ok, :awaiting_choice} = PromptLifecycle.transition(:no_prompt, :open_prompt)

      assert {:ok, :validating_choice} =
               PromptLifecycle.transition(:awaiting_choice, :submit_choice)

      assert {:ok, :applying_choice} =
               PromptLifecycle.transition(:validating_choice, :choice_valid)

      assert {:ok, :prompt_complete} =
               PromptLifecycle.transition(:applying_choice, :finish_prompt)

      assert {:ok, :no_prompt} = PromptLifecycle.transition(:prompt_complete, :clear_prompt)
    end
  end

  describe "card lifecycle" do
    test "allows deck to hand to basic in play" do
      assert {:ok, :in_hand} = CardLifecycle.transition(:in_deck, :draw)
      assert {:ok, :in_play_basic} = CardLifecycle.transition(:in_hand, :play_basic)
    end

    test "rejects recovering a card from lost zone" do
      assert {:error, %IllegalTransition{state: :lost_zone, event: :recover_to_hand, allowed: []}} =
               CardLifecycle.transition(:lost_zone, :recover_to_hand)
    end
  end

  describe "zone movement" do
    test "allows hand to bench movement" do
      assert {:ok, :bench} = ZoneMovement.transition(:hand, :bench)
    end

    test "rejects lost zone movement" do
      assert {:error, %IllegalTransition{state: :lost_zone, event: :hand, allowed: []}} =
               ZoneMovement.transition(:lost_zone, :hand)
    end
  end
end
