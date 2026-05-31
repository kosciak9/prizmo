defmodule Prizmo.TcgEngine.Snapshot do
  @moduledoc false

  alias Prizmo.TcgEngine
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  def dump(game_id) when is_binary(game_id) do
    with {:ok, game} <- get_game(game_id),
         {:ok, players} <- list_players(game_id),
         {:ok, setup} <- maybe_get_setup(game_id),
         {:ok, turns} <- list_turns(game_id),
         {:ok, cards} <- list_cards(game_id),
         {:ok, pending_effects} <- list_pending_effects(game_id),
         {:ok, prompts} <- list_prompts(game_id) do
      {:ok,
       %{
         "game" => game_snapshot(game),
         "players" => Enum.map(players, &player_snapshot/1),
         "setup" => if(setup, do: setup_snapshot(setup)),
         "turns" => Enum.map(turns, &turn_snapshot/1),
         "cards" => Enum.map(cards, &card_snapshot/1),
         "pending_effects" => Enum.map(pending_effects, &pending_effect_snapshot/1),
         "prompts" => Enum.map(prompts, &prompt_snapshot/1)
       }}
    end
  end

  defp get_game(game_id) do
    case TcgEngine.get_game_by_id(game_id) do
      {:ok, %Game{} = game} -> {:ok, game}
      {:ok, nil} -> {:error, :game_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_get_setup(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one()
  end

  defp list_players(game_id) do
    GamePlayer
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(player_id: :asc)
    |> Ash.read()
  end

  defp list_turns(game_id) do
    Turn
    |> Ash.Query.filter(game_id == ^game_id and visible? == true)
    |> Ash.Query.sort(turn_number: :asc)
    |> Ash.read()
  end

  defp list_cards(game_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(owner_player_id: :asc, zone: :asc, position: :asc, instance_id: :asc)
    |> Ash.read()
  end

  defp list_pending_effects(game_id) do
    PendingEffect
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read()
  end

  defp list_prompts(game_id) do
    Prompt
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read()
  end

  defp game_snapshot(%Game{} = game) do
    %{
      "id" => game.id,
      "status" => Atom.to_string(game.status),
      "active_player_id" => game.active_player_id,
      "first_player_id" => game.first_player_id,
      "winner_player_id" => game.winner_player_id,
      "flow_state" => Atom.to_string(game.flow_state),
      "coin_toss_calling_player_id" => game.coin_toss_calling_player_id,
      "coin_toss_call" => if(game.coin_toss_call, do: Atom.to_string(game.coin_toss_call)),
      "coin_toss_result" => if(game.coin_toss_result, do: Atom.to_string(game.coin_toss_result)),
      "coin_toss_winner_player_id" => game.coin_toss_winner_player_id,
      "starting_player_chosen_by_player_id" => game.starting_player_chosen_by_player_id,
      "cursor_index" => game.cursor_index,
      "latest_event_index" => game.latest_event_index
    }
  end

  defp player_snapshot(%GamePlayer{} = player) do
    %{
      "id" => player.id,
      "player_id" => player.player_id,
      "deck_key" => player.deck_key,
      "energy_attached_this_turn?" => player.energy_attached_this_turn?,
      "supporter_played_this_turn?" => player.supporter_played_this_turn?,
      "retreated_this_turn?" => player.retreated_this_turn?,
      "ace_spec_played_this_game?" => player.ace_spec_played_this_game?,
      "setup_ready?" => player.setup_ready?
    }
  end

  defp setup_snapshot(%Setup{} = setup) do
    %{"id" => setup.id, "status" => Atom.to_string(setup.status)}
  end

  defp turn_snapshot(%Turn{} = turn) do
    %{
      "id" => turn.id,
      "turn_number" => turn.turn_number,
      "active_player_id" => turn.active_player_id,
      "status" => Atom.to_string(turn.status),
      "visible?" => turn.visible?,
      "pending_attack_id" =>
        if(turn.pending_attack_id, do: Atom.to_string(turn.pending_attack_id)),
      "pending_attacker_card_instance_id" => turn.pending_attacker_card_instance_id,
      "pending_defender_card_instance_id" => turn.pending_defender_card_instance_id
    }
  end

  defp card_snapshot(%CardInstance{} = card) do
    %{
      "id" => card.id,
      "game_player_id" => card.game_player_id,
      "owner_player_id" => card.owner_player_id,
      "instance_id" => card.instance_id,
      "card_id" => card.card_id,
      "zone" => Atom.to_string(card.zone),
      "position" => card.position,
      "damage" => card.damage,
      "status" => if(card.status, do: Atom.to_string(card.status)),
      "markers" => card.markers,
      "attached_to_card_instance_id" => card.attached_to_card_instance_id,
      "evolves_from_card_instance_id" => card.evolves_from_card_instance_id,
      "turn_entered_play" => card.turn_entered_play
    }
  end

  defp pending_effect_snapshot(%PendingEffect{} = pending_effect) do
    %{
      "id" => pending_effect.id,
      "source_type" => Atom.to_string(pending_effect.source_type),
      "source_card_instance_id" => pending_effect.source_card_instance_id,
      "source_card_id" => pending_effect.source_card_id,
      "controller_player_id" => pending_effect.controller_player_id,
      "current_player_id" => pending_effect.current_player_id,
      "effect_key" =>
        if(pending_effect.effect_key, do: Atom.to_string(pending_effect.effect_key)),
      "step" => pending_effect.step,
      "state" => pending_effect.state,
      "status" => Atom.to_string(pending_effect.status)
    }
  end

  defp prompt_snapshot(%Prompt{} = prompt) do
    %{
      "id" => prompt.id,
      "turn_id" => prompt.turn_id,
      "pending_effect_id" => prompt.pending_effect_id,
      "prompt_type" => prompt.prompt_type,
      "player_id" => prompt.player_id,
      "payload" => prompt.payload,
      "status" => Atom.to_string(prompt.status)
    }
  end
end
