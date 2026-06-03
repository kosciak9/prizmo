defmodule Prizmo.TcgEngine.ToolEffects do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  @handheld_fan_card_id "TWM-150"

  @supported_tool_effect_types [
    :retreat_cost_reduction,
    :bonus_attack_damage_to_pokemon_ex_if_attacker_has_no_rule_box,
    :move_energy_from_attacker_to_defender_bench_on_damage,
    :bench_limit_8_with_tera_in_play_else_discard_to_5
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
    with true <- Map.get(damage_result, :damage, 0) > 0,
         true <- handheld_fan_attached?(game_id, defender_card),
         {:ok, energy_card} <- get_handheld_fan_energy_card(game_id, attacker_card, opts),
         {:ok, bench_target} <- get_handheld_fan_bench_target(game_id, defender_card, opts) do
      move_energy_to_bench(game_id, energy_card, bench_target)
    else
      false -> {:ok, nil}
      {:error, _reason} = error -> error
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

  def retreat_cost_reductions(attached_cards) when is_list(attached_cards) do
    Enum.flat_map(attached_cards, fn
      %CardInstance{} = card ->
        case retreat_cost_reduction(card.card_id) do
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

  def retreat_cost_reduction(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: :retreat_cost_reduction, energy_type: :colorless, amount: amount}
       }}
      when is_integer(amount) and amount > 0 ->
        amount

      {:ok, _card} ->
        0

      {:error, _reason} ->
        0
    end
  end
end
