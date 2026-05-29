defmodule Prizmo.TcgEngine.Requirements do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.PendingEffect
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Turn

  def require_card_owned_by_player(%CardInstance{} = card, player_id) do
    if card.owner_player_id == player_id do
      :ok
    else
      {:error, :card_not_owned_by_player}
    end
  end

  def require_card_zone(%CardInstance{} = card, zone) do
    if card.zone == zone do
      :ok
    else
      {:error, {:invalid_card_zone, card.zone, zone}}
    end
  end

  def require_card_id(%CardInstance{card_id: card_id}, card_id), do: :ok

  def require_card_id(%CardInstance{} = card, expected_card_id),
    do: {:error, {:wrong_card_for_action, expected_card_id, card.card_id}}

  def require_game_status(%Game{} = game, status) do
    if game.status == status do
      :ok
    else
      {:error, {:invalid_game_status, game.status, status}}
    end
  end

  def require_active_player(%Game{} = game, player_id) do
    if game.active_player_id == player_id do
      :ok
    else
      {:error, :not_active_player}
    end
  end

  def require_turn_player(%Turn{} = turn, player_id) do
    if turn.active_player_id == player_id do
      :ok
    else
      {:error, :not_turn_player}
    end
  end

  def require_prompt_awaiting_player(
        %Prompt{status: :awaiting_choice, player_id: player_id},
        player_id
      ), do: :ok

  def require_prompt_awaiting_player(%Prompt{status: status}, _player_id)
      when status != :awaiting_choice,
      do: {:error, {:prompt_not_awaiting_choice, status}}

  def require_prompt_awaiting_player(%Prompt{player_id: expected_player_id}, player_id),
    do: {:error, {:prompt_wrong_player, expected_player_id, player_id}}

  def require_pending_effect_status(%PendingEffect{status: status}, status), do: :ok

  def require_pending_effect_status(%PendingEffect{status: status}, expected_status),
    do: {:error, {:pending_effect_wrong_status, status, expected_status}}

  def prompt_choice_key(%Prompt{payload: payload}), do: Map.fetch!(payload, "choice_key")

  def require_supporter_available(%GamePlayer{} = player, %{trainer_type: :supporter}) do
    if player.supporter_played_this_turn? do
      {:error, :supporter_already_played_this_turn}
    else
      :ok
    end
  end

  def require_supporter_available(%GamePlayer{}, _metadata), do: :ok

  def require_ace_spec_available(%GamePlayer{} = player, %{ace_spec?: true}) do
    if player.ace_spec_played_this_game? do
      {:error, :ace_spec_already_played_this_game}
    else
      :ok
    end
  end

  def require_ace_spec_available(%GamePlayer{}, _metadata), do: :ok

  def require_energy_not_attached_this_turn(%GamePlayer{} = player) do
    if player.energy_attached_this_turn? do
      {:error, :energy_already_attached_this_turn}
    else
      :ok
    end
  end

  def require_evolution_allowed_this_turn(%Turn{} = turn) do
    if turn.turn_number > 1 do
      :ok
    else
      {:error, :cannot_evolve_on_first_turn}
    end
  end

  def require_can_evolve_target(%CardInstance{} = target_card, turn_number) do
    cond do
      is_nil(target_card.turn_entered_play) ->
        {:error, :target_play_turn_unknown}

      target_card.turn_entered_play >= turn_number ->
        {:error, :target_entered_play_this_turn}

      true ->
        :ok
    end
  end

  def require_not_retreated_this_turn(%GamePlayer{} = player) do
    if player.retreated_this_turn? do
      {:error, :already_retreated_this_turn}
    else
      :ok
    end
  end

  def require_can_attack(%CardInstance{status: status}) when status in [:asleep, :paralyzed] do
    {:error, {:cannot_attack_while, status}}
  end

  def require_can_attack(%CardInstance{}), do: :ok

  def require_can_retreat(%CardInstance{status: status}) when status in [:asleep, :paralyzed] do
    {:error, {:cannot_retreat_while, status}}
  end

  def require_can_retreat(%CardInstance{}), do: :ok

  def require_supported_status(nil), do: :ok

  def require_supported_status(status)
      when status in [:asleep, :burned, :confused, :paralyzed, :poisoned], do: :ok

  def require_supported_status(status), do: {:error, {:unsupported_status, status}}

  def require_attached_to(%CardInstance{} = card, target_card_instance_id) do
    if card.attached_to_card_instance_id == target_card_instance_id do
      :ok
    else
      {:error, :card_not_attached_to_active}
    end
  end

  def require_all_owned_in_zone(cards, player_id, zone) do
    cards
    |> Enum.map(fn card ->
      with :ok <- require_card_owned_by_player(card, player_id) do
        require_card_zone(card, zone)
      end
    end)
    |> collect_ok_results()
  end

  def require_in_play_pokemon_zone(%CardInstance{} = card) do
    if card.zone in [:active, :bench] do
      :ok
    else
      {:error, {:invalid_attachment_target_zone, card.zone}}
    end
  end

  def evolve_action_for_zone(:active), do: :evolve_to_active
  def evolve_action_for_zone(:bench), do: :evolve_to_bench

  def require_retreat_cost_paid(retreat_cost, energy_card_instance_ids) do
    cond do
      length(Enum.uniq(energy_card_instance_ids)) != length(energy_card_instance_ids) ->
        {:error, :duplicate_retreat_energy}

      length(energy_card_instance_ids) < retreat_cost ->
        {:error, {:insufficient_retreat_energy, retreat_cost}}

      true ->
        :ok
    end
  end

  def require_max_count(values, max_count, error_tag) do
    if length(values) <= max_count do
      :ok
    else
      {:error, {error_tag, length(values)}}
    end
  end

  def require_exact_count(values, count, error_tag) do
    if length(values) == count do
      :ok
    else
      {:error, {error_tag, length(values)}}
    end
  end

  def require_unique_ids(ids) do
    if length(Enum.uniq(ids)) == length(ids) do
      :ok
    else
      {:error, :duplicate_card_instance_ids}
    end
  end

  def require_id_not_in(id, ids) do
    if id in ids do
      {:error, :action_card_cannot_pay_own_discard_cost}
    else
      :ok
    end
  end

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end
end
