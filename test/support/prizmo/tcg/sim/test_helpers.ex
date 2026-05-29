defmodule Prizmo.Tcg.Sim.TestHelpers do
  @moduledoc false

  alias Prizmo.Tcg.Sim.Action
  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.Tcg.Sim.Engine

  def setup_open_game(deck_a, deck_b, opts \\ []) do
    player_a = Keyword.get(opts, :player_a, :player_a)
    player_b = Keyword.get(opts, :player_b, :player_b)
    active_player = Keyword.get(opts, :active_player, player_a)

    active_a = Keyword.get_lazy(opts, :active_a, fn -> first_basic_card_id!(deck_a) end)
    active_b = Keyword.get_lazy(opts, :active_b, fn -> first_basic_card_id!(deck_b) end)

    state =
      Engine.new_game(
        active_player: active_player,
        players: [
          {player_a, deck_with_opening_active(deck_a, active_a)},
          {player_b, deck_with_opening_active(deck_b, active_b)}
        ]
      )

    with {:ok, state} <- Engine.apply_action(state, %Action{type: :start_setup}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :draw_opening_hand}),
         {:ok, state} <- choose_active(state, player_a, active_a),
         {:ok, state} <- choose_active(state, player_b, active_b),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :place_prizes}),
         {:ok, state} <- Engine.apply_action(state, %Action{type: :complete_setup}),
         {:ok, state} <-
           Engine.apply_action(state, %Action{type: :draw_for_turn, player_id: active_player}) do
      Engine.apply_action(state, %Action{type: :open_action_window})
    end
  end

  def deck_with_opening_active(deck_module, active_card_id) do
    full_deck_ids = deck_module.card_ids()

    opening =
      full_deck_ids
      |> Enum.reject(&(&1 == active_card_id))
      |> Enum.take(6)
      |> then(&[active_card_id | &1])

    deck_with_prefix(opening, full_deck_ids)
  end

  def first_basic_card_id!(deck_module) do
    Enum.find(deck_module.card_ids(), &CardRegistry.basic_pokemon?/1) ||
      raise ArgumentError, "deck #{inspect(deck_module)} has no Basic Pokémon"
  end

  def choose_active(state, player_id, card_id) do
    card = card_in_hand!(state, player_id, card_id)

    Engine.apply_action(state, %Action{
      type: :choose_active_from_hand,
      player_id: player_id,
      params: %{instance_id: card.instance_id}
    })
  end

  def card_in_hand!(state, player_id, card_id) do
    Enum.find(state.players[player_id].hand, &(&1.card_id == card_id)) ||
      raise ArgumentError, "#{card_id} not found in #{player_id} hand"
  end

  def deck_with_prefix(prefix, full_deck_ids) do
    remainder = Enum.reduce(prefix, full_deck_ids, &remove_one/2)
    prefix ++ remainder
  end

  def remove_one(card_id, card_ids) do
    {before_match, [_match | after_match]} = Enum.split_while(card_ids, &(&1 != card_id))
    before_match ++ after_match
  end
end
