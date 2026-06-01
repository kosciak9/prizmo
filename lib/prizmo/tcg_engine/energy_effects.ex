defmodule Prizmo.TcgEngine.EnergyEffects do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.EventPayloads
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer

  @type effect_event :: %{type: atom(), payload: map()}

  @spec after_attach_from_hand(Game.t(), GamePlayer.t(), CardInstance.t(), CardInstance.t()) ::
          {:ok, effect_event() | nil} | {:error, term()}
  def after_attach_from_hand(
        %Game{} = game,
        %GamePlayer{} = player,
        %CardInstance{} = energy_card,
        %CardInstance{} = target_card
      ) do
    with {:ok, catalog_card} <- CardCatalog.fetch(energy_card.card_id) do
      case Map.get(catalog_card, :effect) do
        nil ->
          {:ok, nil}

        %{type: :prevent_opponent_attack_effects_to_attached_pokemon} ->
          {:ok, nil}

        %{type: :team_rocket_energy_attachment_and_dual_provides} ->
          require_team_rocket_energy_target(energy_card, target_card)

        %{type: effect_type}
        when effect_type in [
               :grass_pokemon_hp_plus_20_energy,
               :bench_basic_psychic_from_deck_when_attached_to_psychic
             ] ->
          {:ok, nil}

        %{type: :draw_cards_on_attach_from_hand, count: count}
        when is_integer(count) and count > 0 ->
          draw_cards_on_attach(game, player, energy_card, target_card, count)

        %{type: effect_type} ->
          {:error, {:unsupported_energy_effect, energy_card.card_id, effect_type}}

        effect ->
          {:error, {:invalid_energy_effect, energy_card.card_id, effect}}
      end
    end
  end

  defp require_team_rocket_energy_target(
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card
       ) do
    with {:ok, target_catalog_card} <- CardCatalog.fetch(target_card.card_id) do
      if team_rocket_pokemon?(target_catalog_card) do
        {:ok, nil}
      else
        {:error,
         {:team_rocket_energy_requires_team_rocket_pokemon, energy_card.card_id,
          target_card.card_id}}
      end
    end
  end

  defp team_rocket_pokemon?(%{supertype: :pokemon, name: "Team Rocket's " <> _name}), do: true
  defp team_rocket_pokemon?(_card), do: false

  defp draw_cards_on_attach(
         %Game{} = game,
         %GamePlayer{} = player,
         %CardInstance{} = energy_card,
         %CardInstance{} = target_card,
         count
       ) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, count),
         :ok <- require_enough_deck_cards(cards, count),
         {:ok, starting_position} <-
           CardStore.next_hand_position_result(game.id, player.player_id),
         {:ok, drawn_cards} <- draw_cards_to_hand(cards, starting_position) do
      {:ok,
       %{
         type: :energy_attach_effect_drawn,
         payload: %{
           energy_card_id: energy_card.card_id,
           energy_card_instance_id: energy_card.id,
           target_card_instance_id: target_card.id,
           effect_type: "draw_cards_on_attach_from_hand",
           card_count: length(drawn_cards),
           cards: EventPayloads.moved_cards(drawn_cards, :deck, :hand)
         }
       }}
    end
  end

  defp require_enough_deck_cards(cards, count) when length(cards) == count, do: :ok

  defp require_enough_deck_cards(cards, count),
    do: {:error, {:cannot_draw_energy_attach_effect_from_deck, count, length(cards)}}

  defp draw_cards_to_hand(cards, starting_position) do
    cards
    |> Enum.with_index(starting_position)
    |> Enum.map(fn {card, position} -> update(card, :draw_to_hand, %{position: position}) end)
    |> collect_results()
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end
end
