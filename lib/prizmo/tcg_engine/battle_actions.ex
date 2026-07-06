defmodule Prizmo.TcgEngine.BattleActions do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [require_energy: 1]
  import Prizmo.TcgEngine.Operation, only: [update: 3]
  import Prizmo.TcgEngine.Requirements, only: [require_attached_to: 2, require_card_zone: 2]

  alias Prizmo.TcgEngine.AttackPrevention
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.HpEffects
  alias Prizmo.TcgEngine.TeraBenchProtection
  alias Prizmo.TcgEngine.ToolEffects
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @cornerstone_mask_ogerpon_ex_card_id "TWM-112"
  @cornerstone_stance_effect_id "cornerstone_stance"

  def attached_energy_cards_for_retreat(game_id, active_card_id, energy_card_instance_ids) do
    energy_card_instance_ids
    |> Enum.map(fn energy_card_instance_id ->
      with {:ok, card} <- CardStore.get_card(game_id, energy_card_instance_id),
           :ok <- require_card_zone(card, :attached),
           :ok <- require_attached_to(card, active_card_id),
           :ok <- require_energy(card.card_id) do
        {:ok, card}
      end
    end)
    |> collect_results()
  end

  def discard_retreat_energy(game_id, player_id, energy_cards) do
    energy_cards
    |> Enum.map(fn energy_card ->
      with {:ok, position} <- CardStore.next_discard_position(game_id, player_id) do
        update(energy_card, :discard, %{position: position, attached_to_card_instance_id: nil})
      end
    end)
    |> collect_results()
  end

  def knockout_prize_count(%CardInstance{} = target_card) do
    with {:ok, card} <- CardCatalog.fetch(target_card.card_id) do
      {:ok, prize_count_for_card(card)}
    end
  end

  def knockout_prize_count_for_opponent_attack(game_id, %CardInstance{} = target_card)
      when is_binary(game_id) do
    with {:ok, base_prize_count} <- knockout_prize_count(target_card) do
      reduction = ToolEffects.knockout_prize_reduction(game_id, target_card)
      {:ok, max(base_prize_count - reduction, 0)}
    end
  end

  def knockout_prize_count_for_opponent_attack(
        game_id,
        %CardInstance{} = attacker_card,
        %CardInstance{} = target_card
      )
      when is_binary(game_id) do
    with {:ok, base_prize_count} <- knockout_prize_count(target_card) do
      reduction = ToolEffects.knockout_prize_reduction(game_id, target_card)

      with {:ok, briar_bonus} <- briar_bonus_prize_count(game_id, attacker_card, target_card) do
        {:ok, max(base_prize_count - reduction, 0) + briar_bonus}
      end
    end
  end

  def take_knockout_prizes(_game_id, _player_id, 0), do: {:ok, []}

  def take_knockout_prizes(game_id, player_id, count)
      when is_binary(game_id) and is_binary(player_id) and is_integer(count) and count > 0 do
    with {:ok, prizes} <- CardStore.cards_in_zone(game_id, player_id, :prize) do
      prizes
      |> Enum.take(count)
      |> Enum.map(fn prize_card ->
        with {:ok, position} <- CardStore.next_hand_position_result(game_id, player_id) do
          update(prize_card, :take_prize, %{position: position})
        end
      end)
      |> collect_results()
    end
  end

  def resolve_replacement_active_after_knockout(game_id, player_id)
      when is_binary(game_id) and is_binary(player_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      replacement_resolution(active_cards, bench_cards)
    end
  end

  def apply_attack_damage(game_id, attacking_player_id, target_card, damage, opts \\ []) do
    damage = damage || 0

    case maybe_prevented_attack_damage_result(
           game_id,
           attacking_player_id,
           target_card,
           damage,
           opts
         ) do
      {:ok, damage_result} ->
        {:ok, damage_result}

      :not_prevented ->
        new_damage = target_card.damage + damage

        with {:ok, knocked_out?} <- HpEffects.damage_knocks_out?(game_id, target_card, new_damage),
             {:ok, knockout_prize_count} <-
               maybe_attack_knockout_prize_count(
                 game_id,
                 attacking_player_id,
                 target_card,
                 knocked_out?
               ),
             {:ok, _target_card} <- update(target_card, :set_damage, %{damage: new_damage}),
             {:ok, knocked_out?} <-
               maybe_knock_out(game_id, attacking_player_id, target_card, knocked_out?) do
          {:ok,
           maybe_put_knockout_prize_count(
             %{damage: damage, resulting_damage: new_damage, knocked_out?: knocked_out?},
             knockout_prize_count
           )}
        end
    end
  end

  defp maybe_prevented_attack_damage_result(
         game_id,
         attacking_player_id,
         %CardInstance{} = target_card,
         damage,
         opts
       ) do
    if Keyword.get(opts, :ignore_effects_on_target?, false) do
      :not_prevented
    else
      prevented_attack_damage_result(game_id, attacking_player_id, target_card, damage)
    end
  end

  defp maybe_attack_knockout_prize_count(_game_id, _attacking_player_id, _target_card, false),
    do: {:ok, nil}

  defp maybe_attack_knockout_prize_count(
         game_id,
         attacking_player_id,
         %CardInstance{} = target_card,
         true
       ) do
    with {:ok, attacker_card} <- active_attacker_card(game_id, attacking_player_id) do
      knockout_prize_count_for_opponent_attack(game_id, attacker_card, target_card)
    end
  end

  defp maybe_put_knockout_prize_count(payload, knockout_prize_count)
       when is_integer(knockout_prize_count) and knockout_prize_count >= 0 do
    Map.put(payload, :knockout_prize_count, knockout_prize_count)
  end

  defp maybe_put_knockout_prize_count(payload, _knockout_prize_count), do: payload

  defp prevented_attack_damage_result(game_id, attacking_player_id, target_card, damage) do
    if TeraBenchProtection.prevents_attack_damage?(target_card) do
      {:ok, TeraBenchProtection.prevented_attack_damage_result(target_card, damage)}
    else
      case cornerstone_stance_prevention_result(
             game_id,
             attacking_player_id,
             target_card,
             damage
           ) do
        {:ok, _result} = ok ->
          ok

        :not_prevented ->
          prevented_attack_damage_by_marker_result(
            game_id,
            attacking_player_id,
            target_card,
            damage
          )
      end
    end
  end

  defp cornerstone_stance_prevention_result(
         game_id,
         attacking_player_id,
         %CardInstance{
           card_id: @cornerstone_mask_ogerpon_ex_card_id,
           owner_player_id: owner_player_id,
           zone: :active
         } =
           target_card,
         damage
       )
       when owner_player_id != attacking_player_id do
    with {:ok, attacker_card} <- active_attacker_card(game_id, attacking_player_id),
         true <- attacker_has_ability?(attacker_card) do
      {:ok,
       %{
         damage: 0,
         prevented_damage: damage,
         resulting_damage: target_card.damage,
         knocked_out?: false,
         damage_prevented?: true,
         damage_prevention: @cornerstone_stance_effect_id,
         attack_prevention_source_card_id: target_card.card_id,
         attack_prevention_source_card_instance_id: target_card.id,
         attack_prevention_source_effect_id: @cornerstone_stance_effect_id,
         attack_prevention_source_player_id: owner_player_id,
         protected_card_instance_id: target_card.id
       }}
    else
      false -> :not_prevented
      {:error, _reason} -> :not_prevented
    end
  end

  defp cornerstone_stance_prevention_result(
         _game_id,
         _attacking_player_id,
         %CardInstance{},
         _damage
       ), do: :not_prevented

  defp attacker_has_ability?(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{abilities: abilities}} when map_size(abilities) > 0 -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  defp prevented_attack_damage_by_marker_result(game_id, attacking_player_id, target_card, damage) do
    with {:ok, turn} <- TurnStore.current_turn(game_id),
         true <-
           AttackPrevention.damage_and_effects_prevented_this_turn?(
             target_card,
             turn,
             attacking_player_id
           ) do
      {:ok,
       Map.merge(
         %{
           damage: 0,
           prevented_damage: damage,
           resulting_damage: target_card.damage,
           knocked_out?: false,
           damage_prevented?: true
         },
         AttackPrevention.prevention_payload(target_card, turn)
       )}
    else
      _not_prevented -> :not_prevented
    end
  end

  defp maybe_knock_out(_game_id, _attacking_player_id, _target_card, false) do
    {:ok, false}
  end

  defp maybe_knock_out(game_id, _attacking_player_id, target_card, true) do
    with {:ok, _discarded_cards} <- discard_knocked_out_stack(game_id, target_card) do
      {:ok, true}
    end
  end

  defp replacement_resolution([_active_card | _rest], _bench_cards) do
    {:ok,
     %{
       empty_board?: false,
       promoted_card_instance_id: nil,
       replacement_required?: false
     }}
  end

  defp replacement_resolution([], []) do
    {:ok,
     %{
       empty_board?: true,
       promoted_card_instance_id: nil,
       replacement_required?: false
     }}
  end

  defp replacement_resolution([], [bench_card]) do
    with {:ok, promoted_card} <-
           update(bench_card, :promote_to_active, %{position: 1, status: nil}) do
      {:ok,
       %{
         empty_board?: false,
         promoted_card_instance_id: promoted_card.id,
         replacement_required?: false
       }}
    end
  end

  defp replacement_resolution([], bench_cards) do
    {:ok,
     %{
       empty_board?: false,
       promoted_card_instance_id: nil,
       replacement_candidate_card_instance_ids: Enum.map(bench_cards, & &1.id),
       replacement_required?: true
     }}
  end

  defp active_attacker_card(game_id, player_id) do
    with {:ok, cards} <- CardStore.list_cards(game_id) do
      case Enum.filter(cards, &(&1.owner_player_id == player_id and &1.zone == :active)) do
        [active_card] -> {:ok, active_card}
        [] -> {:error, :missing_active_pokemon}
        _multiple -> {:error, :ambiguous_active_pokemon}
      end
    end
  end

  defp briar_bonus_prize_count(
         game_id,
         %CardInstance{} = attacker_card,
         %CardInstance{} = target_card
       ) do
    cond do
      attacker_card.owner_player_id == target_card.owner_player_id ->
        {:ok, 0}

      target_card.zone != :active ->
        {:ok, 0}

      not CardCatalog.tera_pokemon?(attacker_card.card_id) ->
        {:ok, 0}

      true ->
        with {:ok, turn} <- TurnStore.current_turn(game_id),
             {:ok, events} <-
               card_play_completed_events_for_turn(
                 game_id,
                 turn.id,
                 attacker_card.owner_player_id
               ) do
          {:ok, if(Enum.any?(events, &briar_card_play?/1), do: 1, else: 0)}
        end
    end
  end

  defp card_play_completed_events_for_turn(game_id, turn_id, player_id) do
    GameEvent
    |> Ash.Query.filter(
      game_id == ^game_id and turn_id == ^turn_id and player_id == ^player_id and
        type == "card_play_completed"
    )
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp briar_card_play?(%GameEvent{payload: payload}), do: payload["card_id"] == "SCR-132"

  defp prize_count_for_card(%{supertype: :pokemon, name: name}) when is_binary(name) do
    cond do
      String.starts_with?(name, "Mega ") and String.ends_with?(name, " ex") -> 3
      String.ends_with?(name, " ex") -> 2
      true -> 1
    end
  end

  defp prize_count_for_card(%{supertype: :pokemon, suffix: "ex"}), do: 2

  defp prize_count_for_card(_card), do: 1

  @spec discard_knocked_out_stack(String.t(), CardInstance.t()) ::
          {:ok, [CardInstance.t()]} | {:error, term()}
  def discard_knocked_out_stack(game_id, %CardInstance{} = target_card) do
    with {:ok, stack_cards} <- CardStore.attached_cards(game_id, target_card.id) do
      [target_card | stack_cards]
      |> Enum.map(fn card ->
        with {:ok, position} <- CardStore.next_discard_position(game_id, card.owner_player_id) do
          update(card, :discard, %{
            position: position,
            damage: 0,
            status: nil,
            attached_to_card_instance_id: nil,
            evolves_from_card_instance_id: nil
          })
        end
      end)
      |> collect_results()
    end
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
