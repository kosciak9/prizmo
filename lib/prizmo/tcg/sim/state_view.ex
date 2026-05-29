defmodule Prizmo.Tcg.Sim.StateView do
  @moduledoc """
  JSON-safe view models for the rough TCG simulator UI.

  The simulator structs intentionally keep engine-native fields such as atoms,
  history snapshots, RNG state, and nested card trees. This module exposes a
  shallow, display-oriented shape suitable for Phoenix Channel payloads.
  """

  alias Prizmo.Tcg.Sim.CardInstance
  alias Prizmo.Tcg.Sim.CardRegistry
  alias Prizmo.Tcg.Sim.GameState
  alias Prizmo.Tcg.Sim.PlayerState

  @type json_value ::
          nil | boolean() | number() | String.t() | [json_value()] | %{String.t() => json_value()}

  def render(%GameState{} = state) do
    %{
      "activePlayer" => state.active_player,
      "firstPlayer" => state.first_player,
      "gameLifecycle" => stringify(state.game_lifecycle),
      "turnLifecycle" => stringify(state.turn_lifecycle),
      "promptLifecycle" => stringify(state.prompt_lifecycle),
      "turnNumber" => state.turn_number,
      "winner" => state.winner,
      "stadium" => render_card(state.stadium),
      "pendingPrompts" => stringify_term(state.pending_prompts),
      "pendingAttack" => stringify_term(state.pending_attack),
      "pendingPrizes" => stringify_term(state.pending_prizes),
      "log" => Enum.take(state.log, 60),
      "players" => render_players(state.players)
    }
  end

  defp render_players(players) do
    players
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new(fn {player_id, player} -> {player_id, render_player(player)} end)
  end

  defp render_player(%PlayerState{} = player) do
    %{
      "id" => player.id,
      "expectedCardCount" => player.expected_card_count,
      "deckCount" => length(player.deck),
      "hand" => render_cards(player.hand),
      "prizes" => render_cards(player.prizes),
      "prizeCount" => length(player.prizes),
      "discard" => render_cards(player.discard),
      "discardCount" => length(player.discard),
      "lostZone" => render_cards(player.lost_zone),
      "active" => render_card(player.active),
      "bench" => render_cards(player.bench),
      "mulligansTaken" => player.mulligans_taken,
      "mulliganBonusDrawsTaken" => player.mulligan_bonus_draws_taken,
      "markers" => render_markers(player.markers),
      "flags" => %{
        "supporterPlayed" => player.supporter_played?,
        "itemCardsLocked" => player.item_cards_locked?,
        "energyAttached" => player.energy_attached?,
        "retreated" => player.retreated?
      }
    }
  end

  defp render_cards(cards), do: Enum.map(cards, &render_card/1)

  defp render_card(nil), do: nil

  defp render_card(%CardInstance{} = card) do
    metadata = display_metadata(card.card_id)

    %{
      "instanceId" => card.instance_id,
      "cardId" => card.card_id,
      "owner" => card.owner,
      "lifecycle" => stringify(card.lifecycle),
      "zone" => stringify(card.zone),
      "damage" => card.damage,
      "status" => stringify(card.status),
      "turnEnteredPlay" => card.turn_entered_play,
      "attachments" => Enum.map(card.attachments, &render_attached_card/1),
      "tool" => render_attached_card(card.tool),
      "evolvedFrom" => Enum.map(card.evolved_from, &render_attached_card/1),
      "card" => metadata
    }
  end

  defp render_attached_card(nil), do: nil

  defp render_attached_card(%CardInstance{} = card) do
    %{
      "instanceId" => card.instance_id,
      "cardId" => card.card_id,
      "owner" => card.owner,
      "zone" => stringify(card.zone),
      "damage" => card.damage,
      "status" => stringify(card.status),
      "card" => display_metadata(card.card_id)
    }
  end

  defp display_metadata(card_id) do
    case CardRegistry.fetch(card_id) do
      {:ok, card} ->
        %{
          "id" => card.id,
          "name" => card.name,
          "supertype" => stringify(card.supertype),
          "type" => stringify(Map.get(card, :type)),
          "types" => stringify_list(Map.get(card, :types, [])),
          "hp" => card.hp,
          "stage" => stringify(card.stage),
          "trainerType" => stringify(card.trainer_type),
          "energyType" => stringify(card.energy_type || Map.get(card, :tcgdex_energy_type)),
          "image" => card.image,
          "imageLow" => image_variant(card.image, "low"),
          "imageHigh" => image_variant(card.image, "high"),
          "attacks" => render_named_entries(card.attacks),
          "abilities" => render_named_entries(card.abilities)
        }

      {:error, _reason} ->
        %{
          "id" => card_id,
          "name" => card_id,
          "supertype" => nil,
          "image" => nil,
          "imageLow" => nil,
          "imageHigh" => nil,
          "attacks" => [],
          "abilities" => []
        }
    end
  end

  defp render_named_entries(entries) when is_map(entries) do
    entries
    |> Enum.sort_by(fn {id, _entry} -> to_string(id) end)
    |> Enum.map(fn {id, entry} ->
      %{
        "id" => stringify(id),
        "name" => Map.get(entry, :name),
        "damage" => stringify_term(Map.get(entry, :damage)),
        "cost" => stringify_list(Map.get(entry, :cost, [])),
        "text" => Map.get(entry, :text) || Map.get(entry, :raw_text)
      }
    end)
  end

  defp render_named_entries(_entries), do: []

  defp render_markers(%MapSet{} = markers) do
    markers
    |> MapSet.to_list()
    |> Enum.map(&stringify_term/1)
    |> Enum.sort()
  end

  defp image_variant(nil, _variant), do: nil
  defp image_variant(image, variant), do: image <> "/" <> variant <> ".webp"

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp stringify_list(values) when is_list(values), do: Enum.map(values, &stringify/1)
  defp stringify_list(_values), do: []

  defp stringify_term(nil), do: nil
  defp stringify_term(value) when is_binary(value), do: value
  defp stringify_term(value) when is_number(value) or is_boolean(value), do: value
  defp stringify_term(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_term(value), do: inspect(value)
end
