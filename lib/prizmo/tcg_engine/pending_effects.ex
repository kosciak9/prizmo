defmodule Prizmo.TcgEngine.PendingEffects do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [create: 3, update: 3]

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.ChoiceValidator
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PendingEffect

  require Ash.Query

  def get(game_id, nil) when is_binary(game_id), do: {:error, :pending_effect_not_found}

  def get(game_id, pending_effect_id) when is_binary(game_id) and is_binary(pending_effect_id) do
    case PendingEffect
         |> Ash.Query.filter(game_id == ^game_id and id == ^pending_effect_id)
         |> Ash.read_one() do
      {:ok, %PendingEffect{} = pending_effect} -> {:ok, pending_effect}
      {:ok, nil} -> {:error, :pending_effect_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def awaiting_for_game(game_id) when is_binary(game_id) do
    case PendingEffect
         |> Ash.Query.filter(game_id == ^game_id and status == :awaiting_prompt)
         |> Ash.Query.sort(created_at: :asc)
         |> Ash.Query.limit(1)
         |> Ash.read_one() do
      {:ok, %PendingEffect{} = pending_effect} -> {:ok, pending_effect}
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def resolving_for_game(game_id) when is_binary(game_id) do
    case PendingEffect
         |> Ash.Query.filter(game_id == ^game_id and status == :resolving)
         |> Ash.Query.sort(created_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read_one() do
      {:ok, %PendingEffect{} = pending_effect} -> {:ok, pending_effect}
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def active_for_game(game_id) when is_binary(game_id) do
    case awaiting_for_game(game_id) do
      {:ok, nil} -> resolving_for_game(game_id)
      other -> other
    end
  end

  def upsert_awaiting(
        %Game{} = game,
        %GamePlayer{} = player,
        %CardInstance{} = card,
        choices,
        phase,
        choice_key,
        current_player_id \\ nil
      ) do
    current_player_id = current_player_id || player.player_id

    state = %{
      version: 1,
      kind: :play_card,
      phase: phase,
      player_id: player.player_id,
      card_instance_id: card.id,
      card_id: card.card_id,
      choices: ChoiceValidator.stringify_keys(choices)
    }

    case active_for_game(game.id) do
      {:ok, nil} ->
        create_and_await(game, player, card, state, phase, choice_key, current_player_id)

      {:ok, %PendingEffect{} = pending_effect} ->
        await(pending_effect, state, phase, choice_key, current_player_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete_resolving_for_game(game_id) when is_binary(game_id) do
    case resolving_for_game(game_id) do
      {:ok, nil} ->
        :ok

      {:ok, pending_effect} ->
        with {:ok, _pending_effect} <-
               update(pending_effect, :complete, %{state: pending_effect.state || %{}}) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_and_await(game, player, card, state, phase, choice_key, current_player_id) do
    with {:ok, pending_effect} <-
           create(PendingEffect, :create, %{
             game_id: game.id,
             source_type: :card_effect,
             source_card_instance_id: card.id,
             source_card_id: card.card_id,
             controller_player_id: player.player_id,
             current_player_id: current_player_id,
             effect_key: choice_key,
             step: Atom.to_string(phase),
             state: state
           }) do
      await(pending_effect, state, phase, choice_key, current_player_id)
    end
  end

  defp await(pending_effect, state, phase, choice_key, current_player_id) do
    update(pending_effect, :await_prompt, %{
      current_player_id: current_player_id,
      effect_key: choice_key,
      step: Atom.to_string(phase),
      state: state
    })
  end
end
