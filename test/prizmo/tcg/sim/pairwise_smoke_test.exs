defmodule Prizmo.Tcg.Sim.PairwiseSmokeTest do
  use ExUnit.Case, async: true

  alias Prizmo.Tcg.Data.TCGdex
  alias Prizmo.Tcg.Sim.Invariants
  alias Prizmo.Tcg.Sim.RegistryCoverage
  alias Prizmo.Tcg.Sim.TestHelpers

  @known_decks TCGdex.known_deck_modules()

  test "known deck registry coverage has no unsupported cards" do
    assert RegistryCoverage.report().summary.behavior_statuses == %{implemented: 101}

    assert Enum.all?(RegistryCoverage.deck_reports(), fn deck_report ->
             deck_report.unsupported_card_ids == []
           end)
  end

  for {deck_a, deck_b} <- for(a <- @known_decks, b <- @known_decks, a != b, do: {a, b}) do
    @tag deck_a: deck_a.id(), deck_b: deck_b.id()
    test "#{deck_a.name()} can open against #{deck_b.name()}" do
      assert {:ok, state} = TestHelpers.setup_open_game(unquote(deck_a), unquote(deck_b))

      assert state.game_lifecycle == :in_progress
      assert state.turn_lifecycle == :action_window
      assert state.players.player_a.active
      assert state.players.player_b.active
      assert length(state.players.player_a.prizes) == 6
      assert length(state.players.player_b.prizes) == 6
      assert :ok = Invariants.validate_card_accounting(state)
    end
  end
end
