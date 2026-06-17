defmodule Prizmo.TcgEngine.ToolEffects do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardMetadataRequirements
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.StadiumEffects

  require Ash.Query

  @handheld_fan_card_id "TWM-150"
  @luxray_card_id "TWM-158"

  @supported_tool_effect_types [
    :retreat_cost_reduction,
    :retreat_cost_reduction_with_low_hp_free_retreat,
    :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
    :move_energy_from_attacker_to_defender_bench_on_damage,
    :bench_limit_8_with_tera_in_play_else_discard_to_5,
    :reduce_attack_cost_by_colorless_if_more_prizes_remaining,
    :draw_cards_if_damaged_as_active_by_attack,
    :reduce_opponents_knockout_prize_count_by_one
  ]

  def supported_tool?(%{supertype: :trainer, trainer_type: :tool, effect: %{type: type}})
      when type in @supported_tool_effect_types, do: true

  def supported_tool?(_card), do: false

  def supported_tool_card?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> supported_tool?(card)
      {:error, _reason} -> false
    end
  end

  @doc """
  Returns how many fewer Prize cards an attacking opponent should take when the
  target Pokémon is Knocked Out by damage from that opponent's attack.
  """
  def knockout_prize_reduction(game_id, %CardInstance{} = target_card) when is_binary(game_id) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         {:ok, target_catalog_card} <- CardCatalog.fetch(target_card.card_id),
         {:ok, attachments} <- CardStore.attached_cards(game_id, target_card.id) do
      case Enum.map(attachments, &knockout_prize_reduction_from_tool(&1, target_catalog_card)) do
        [] -> 0
        reductions -> Enum.max(reductions)
      end
    else
      true -> 0
      _other -> 0
    end
  end

  @doc """
  Applies Handheld Fan's effect after attack damage: moves one Energy from the
  attacking Pokémon to the defending player's bench if the defender had TWM-150
  attached and damage was dealt.
  """
  def apply_handheld_fan_if_needed(
        game_id,
        _attacking_player_id,
        attacker_card,
        defender_card,
        damage_result,
        opts
      ) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         true <- Map.get(damage_result, :damage, 0) > 0,
         true <- handheld_fan_attached?(game_id, defender_card),
         {:ok, energy_card} <- get_handheld_fan_energy_card(game_id, attacker_card, opts),
         {:ok, bench_target} <- get_handheld_fan_bench_target(game_id, defender_card, opts) do
      move_energy_to_bench(game_id, energy_card, bench_target)
    else
      true -> {:ok, nil}
      false -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Applies Luxray's effect after attack damage: draws 2 cards for the defender's
  player if the defender's Active had TWM-158 attached and damage was dealt.
  """
  def apply_luxray_draw_if_needed(
        game_id,
        _attacking_player_id,
        _attacker_card,
        defender_card,
        damage_result
      ) do
    with false <- StadiumEffects.tools_have_no_effect?(game_id),
         true <- Map.get(damage_result, :damage, 0) > 0,
         true <- luxray_attached?(game_id, defender_card),
         {:ok, player} <- CardStore.get_player(game_id, defender_card.owner_player_id),
         {:ok, _drawn} <- draw_cards_for_player(game_id, player, 2) do
      {:ok, %{type: :luxray_draw_triggered, count: 2, player_id: player.id}}
    else
      true -> {:ok, nil}
      false -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  defp luxray_attached?(game_id, %CardInstance{id: defender_id}) do
    case CardStore.attached_cards(game_id, defender_id) do
      {:ok, attachments} ->
        Enum.any?(attachments, &(&1.card_id == @luxray_card_id))

      _other ->
        false
    end
  end

  defp draw_cards_for_player(game_id, player, count) do
    with {:ok, cards} <- CardStore.deck_cards_for_player(player.id, count) do
      cards
      |> Enum.map(&CardStore.move_deck_card_to_hand(game_id, player.player_id, &1))
      |> collect_results()
    end
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp handheld_fan_attached?(game_id, %CardInstance{id: defender_id}) do
    case CardStore.attached_cards(game_id, defender_id) do
      {:ok, attachments} ->
        Enum.any?(attachments, &(&1.card_id == @handheld_fan_card_id))

      _other ->
        false
    end
  end

  defp get_handheld_fan_energy_card(game_id, %CardInstance{id: attacker_id}, opts) do
    attachment_id = Map.get(opts, :handheld_fan_attachment_id)

    if is_nil(attachment_id) do
      {:error, :handheld_fan_requires_energy_attachment_id}
    else
      case CardStore.get_card(game_id, attachment_id) do
        {:ok, %CardInstance{zone: :attached, attached_to_card_instance_id: ^attacker_id} = card} ->
          {:ok, card}

        {:ok, _card} ->
          {:error, :handheld_fan_attachment_not_found_on_attacker}

        {:error, _reason} ->
          {:error, :handheld_fan_attachment_not_found}
      end
    end
  end

  defp get_handheld_fan_bench_target(
         game_id,
         %CardInstance{owner_player_id: defender_player_id},
         opts
       ) do
    target_id = Map.get(opts, :handheld_fan_target_id)

    if is_nil(target_id) do
      {:error, :handheld_fan_requires_bench_target_id}
    else
      case CardStore.get_card(game_id, target_id) do
        {:ok, %CardInstance{owner_player_id: ^defender_player_id, zone: :bench} = card} ->
          {:ok, card}

        {:ok, _card} ->
          {:error, :handheld_fan_invalid_bench_target}

        {:error, _reason} ->
          {:error, :handheld_fan_bench_target_not_found}
      end
    end
  end

  defp move_energy_to_bench(game_id, energy_card, bench_target) do
    with {:ok, position} <- CardStore.next_attachment_position(game_id, bench_target.id),
         changeset =
           Ash.Changeset.for_update(energy_card, :reparent_attachment, %{
             attached_to_card_instance_id: bench_target.id,
             position: position
           }),
         {:ok, _moved_energy} <- Ash.update(changeset) do
      {:ok,
       %{
         type: :handheld_fan_energy_moved,
         energy_card_instance_id: energy_card.id,
         from_card_instance_id: energy_card.attached_to_card_instance_id,
         to_card_instance_id: bench_target.id
       }}
    end
  end

  defp knockout_prize_reduction_from_tool(%CardInstance{card_id: card_id}, %{name: target_name})
       when is_binary(target_name) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :reduce_opponents_knockout_prize_count_by_one, amount: amount} = effect
       }}
      when is_integer(amount) and amount > 0 ->
        if attached_pokemon_matches_prize_reduction?(target_name, effect), do: amount, else: 0

      _other ->
        0
    end
  end

  defp knockout_prize_reduction_from_tool(%CardInstance{}, _target_card), do: 0

  defp attached_pokemon_matches_prize_reduction?(target_name, %{
         required_attached_pokemon_name_prefix: prefix
       })
       when is_binary(target_name) and is_binary(prefix) do
    String.starts_with?(target_name, prefix)
  end

  defp attached_pokemon_matches_prize_reduction?(_target_name, %{
         required_attached_pokemon_name_prefix: _prefix
       }),
       do: false

  defp attached_pokemon_matches_prize_reduction?(_target_name, _effect), do: true

  def retreat_cost_reductions(%CardInstance{} = attached_to_card, attached_cards)
      when is_list(attached_cards) do
    Enum.flat_map(attached_cards, fn
      %CardInstance{} = card ->
        case retreat_cost_reduction(attached_to_card, card) do
          amount when amount > 0 ->
            [
              %{
                amount: amount,
                card_id: card.card_id,
                card_instance_id: card.id
              }
            ]

          _amount ->
            []
        end

      _card ->
        []
    end)
  end

  def retreat_cost_reductions(game_id, %CardInstance{} = attached_to_card, attached_cards)
      when is_binary(game_id) and is_list(attached_cards) do
    if StadiumEffects.tools_have_no_effect?(game_id) do
      []
    else
      retreat_cost_reductions(attached_to_card, attached_cards)
    end
  end

  def retreat_cost_reduction(%CardInstance{} = attached_to_card, %CardInstance{card_id: card_id})
      when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :retreat_cost_reduction, energy_type: :colorless, amount: amount}
       }}
      when is_integer(amount) and amount > 0 ->
        amount

      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{
           type: :retreat_cost_reduction_with_low_hp_free_retreat,
           amount: amount,
           remaining_hp_max: remaining_hp_max
         }
       }}
      when is_integer(amount) and amount > 0 and is_integer(remaining_hp_max) and
             remaining_hp_max >= 0 ->
        if remaining_hp_at_most?(attached_to_card, remaining_hp_max) do
          printed_retreat_cost(attached_to_card)
        else
          amount
        end

      {:ok, _card} ->
        0

      {:error, _reason} ->
        0
    end
  end

  defp remaining_hp_at_most?(%CardInstance{card_id: card_id, damage: damage}, max_remaining_hp)
       when is_integer(max_remaining_hp) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, hp: hp}} when is_integer(hp) ->
        max(hp - (damage || 0), 0) <= max_remaining_hp

      _other ->
        false
    end
  end

  defp printed_retreat_cost(%CardInstance{card_id: card_id}) do
    case CardMetadataRequirements.retreat_cost(card_id) do
      {:ok, retreat_cost} when is_integer(retreat_cost) and retreat_cost > 0 -> retreat_cost
      _other -> 0
    end
  end
end
