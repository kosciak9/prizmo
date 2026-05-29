defmodule Prizmo.TcgEngine.MechanicsTest do
  use Prizmo.DataCase, async: true

  alias Prizmo.Tcg.Sim.Decks.Alakazam27147
  alias Prizmo.Tcg.Sim.Decks.Dragapult27431
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameSnapshot
  alias Prizmo.TcgEngine.Mechanics
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  describe "setup flow" do
    test "opening hands can only be drawn once and rejected attempts are not saved" do
      {:ok, game} = create_started_setup_game()

      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} = Mechanics.draw_opening_hand(game)
      assert game.cursor_index == 2
      assert game.latest_event_index == 2
      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
      assert event_types(game.id) == ["start_setup", "draw_opening_hand"]
      assert snapshot_indexes(game.id) == [0, 1, 2]

      assert {:error, _reason} = Mechanics.draw_opening_hand(game)

      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
      assert event_types(game.id) == ["start_setup", "draw_opening_hand"]
      assert snapshot_indexes(game.id) == [0, 1, 2]
    end

    test "undo and redo restore granular snapshots" do
      {:ok, game} = create_started_setup_game()
      {:ok, game} = Mechanics.draw_opening_hand(game)

      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}

      assert {:ok, game} = Mechanics.undo(game)
      assert game.cursor_index == 1
      assert setup_status(game.id) == :waiting_to_draw
      assert counts_by_zone(game.id) == %{deck: 120}

      assert {:ok, game} = Mechanics.redo(game)
      assert game.cursor_index == 2
      assert setup_status(game.id) == :hands_drawn
      assert counts_by_zone(game.id) == %{deck: 106, hand: 14}
    end
  end

  describe "generic play_card/4" do
    test "Ultra Ball-style card resolves with upfront choices and domain fact events" do
      {:ok, game} = create_action_window_game()

      %{ultra_ball: ultra_ball, cost_cards: cost_cards, target: target} =
        stage_ultra_ball_cards(game.id)

      assert {:ok, game} =
               Mechanics.play_card(game, "player_1", ultra_ball.id, %{
                 choices: %{
                   discard_two_from_hand: Enum.map(cost_cards, & &1.id),
                   search_deck_for_pokemon: [target.id]
                 }
               })

      assert game.cursor_index == 11
      assert zone(ultra_ball.id) == :discard
      assert Enum.map(cost_cards, &zone(&1.id)) == [:discard, :discard]
      assert zone(target.id) == :hand

      assert event_types(game.id) == [
               "start_setup",
               "card_play_started",
               "cost_payment_started",
               "cards_moved",
               "cost_paid",
               "cards_moved",
               "effect_started",
               "cards_moved",
               "deck_shuffled",
               "effect_completed",
               "card_play_completed"
             ]
    end

    test "Ultra Ball-style card can suspend for cost and effect prompts" do
      {:ok, game} = create_action_window_game()

      %{ultra_ball: ultra_ball, cost_cards: cost_cards, target: target} =
        stage_ultra_ball_cards(game.id)

      assert {:ok, game} = Mechanics.play_card(game, "player_1", ultra_ball.id, %{})
      assert zone(ultra_ball.id) == :hand

      assert [%PendingEffect{status: :awaiting_prompt} = pending_effect] =
               pending_effects(game.id)

      assert [%Prompt{} = cost_prompt] = prompts(game.id)
      assert cost_prompt.payload["choice_key"] == "discard_two_from_hand"

      assert {:error, {:pending_effect_awaiting_prompt, _id}} =
               Mechanics.play_card(game, "player_1", ultra_ball.id, %{})

      assert {:ok, game} =
               Mechanics.choose_prompt(
                 game,
                 "player_1",
                 cost_prompt.id,
                 Enum.map(cost_cards, & &1.id)
               )

      assert zone(ultra_ball.id) == :discard
      assert Enum.map(cost_cards, &zone(&1.id)) == [:discard, :discard]

      assert [%PendingEffect{status: :awaiting_prompt, id: pending_effect_id}] =
               pending_effects(game.id)

      assert pending_effect_id == pending_effect.id
      assert [_resolved_cost_prompt, %Prompt{} = search_prompt] = prompts(game.id)
      assert search_prompt.payload["choice_key"] == "search_deck_for_pokemon"

      assert {:ok, game} =
               Mechanics.choose_prompt(game, "player_1", search_prompt.id, [target.id])

      assert zone(target.id) == :hand
      assert [%PendingEffect{status: :completed}] = pending_effects(game.id)

      assert event_types(game.id) == [
               "start_setup",
               "card_play_started",
               "cost_payment_started",
               "pending_effect_created",
               "prompt_created",
               "prompt_resolved",
               "cards_moved",
               "cost_paid",
               "cards_moved",
               "effect_started",
               "pending_effect_created",
               "prompt_created",
               "prompt_resolved",
               "cards_moved",
               "deck_shuffled",
               "effect_completed",
               "card_play_completed"
             ]
    end
  end

  defp create_started_setup_game do
    with {:ok, game} <-
           Mechanics.create_game([
             {"player_1", Alakazam27147},
             {"player_2", Dragapult27431}
           ]) do
      Mechanics.start_setup(game)
    end
  end

  defp create_action_window_game do
    with {:ok, game} <-
           Mechanics.create_game([
             {"player_1", Dragapult27431},
             {"player_2", Alakazam27147}
           ]),
         {:ok, game} <- Mechanics.start_setup(game),
         {:ok, game} <- ash_update(game, :complete_setup, %{}),
         {:ok, turn} <-
           ash_create(Turn, :create, %{
             game_id: game.id,
             turn_number: 1,
             active_player_id: "player_1"
           }),
         {:ok, turn} <- ash_update(turn, :draw_for_turn, %{}),
         {:ok, _turn} <- ash_update(turn, :open_action_window, %{}) do
      {:ok, game}
    end
  end

  defp stage_ultra_ball_cards(game_id) do
    ultra_ball = deck_card(game_id, "player_1", "MEG-131")
    target = deck_card(game_id, "player_1", "TWM-128")

    [cost_card_1, cost_card_2 | _rest] =
      deck_cards_except(game_id, "player_1", [ultra_ball.id, target.id])

    {:ok, ultra_ball} = ash_update(ultra_ball, :draw_to_hand, %{position: 1})
    {:ok, cost_card_1} = ash_update(cost_card_1, :draw_to_hand, %{position: 2})
    {:ok, cost_card_2} = ash_update(cost_card_2, :draw_to_hand, %{position: 3})

    %{ultra_ball: ultra_ball, cost_cards: [cost_card_1, cost_card_2], target: target}
  end

  defp deck_card(game_id, player_id, card_id) do
    CardInstance
    |> Ash.Query.filter(
      game_id == ^game_id and owner_player_id == ^player_id and card_id == ^card_id and
        zone == :deck
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> List.first()
  end

  defp deck_cards_except(game_id, player_id, excluded_ids) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == :deck)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!()
    |> Enum.reject(&(&1.id in excluded_ids))
  end

  defp zone(card_id) do
    CardInstance
    |> Ash.Query.filter(id == ^card_id)
    |> Ash.read_one!()
    |> Map.fetch!(:zone)
  end

  defp pending_effects(game_id) do
    PendingEffect
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read!()
  end

  defp prompts(game_id) do
    Prompt
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read!()
  end

  defp ash_create(resource, action, attrs) do
    resource
    |> Ash.Changeset.for_create(action, attrs)
    |> Ash.create()
  end

  defp ash_update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update()
  end

  defp counts_by_zone(game_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read!()
    |> Enum.frequencies_by(& &1.zone)
  end

  defp setup_status(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one!()
    |> Map.fetch!(:status)
  end

  defp event_types(game_id) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
    |> Enum.map(& &1.type)
  end

  defp snapshot_indexes(game_id) do
    GameSnapshot
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read!()
    |> Enum.map(& &1.index)
  end
end
