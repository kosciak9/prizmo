defmodule Prizmo.TcgEngine.EffectRunner do
  @moduledoc false

  alias Prizmo.TcgEngine.ChoiceValidator

  @choice_effect_types [
    :search_deck,
    :switch_opponent_bench_to_active,
    :discard_opponent_special_energy
  ]

  def first_effect(definition) do
    case definition.effects do
      [effect] -> {:ok, effect}
      [] -> {:error, :missing_effect_definition}
      effects -> {:error, {:multiple_effects_not_supported_yet, Enum.map(effects, & &1.key)}}
    end
  end

  def selected_choice(choices, effect) do
    case ChoiceValidator.fetch_choice(choices, effect.key) do
      {:ok, selected_choice} -> {:ok, selected_choice}
      :missing -> maybe_auto_resolve_choice(effect)
    end
  end

  def requires_choice?(%{type: type}), do: type in @choice_effect_types

  def validate_search_deck_selection(effect, target_ids) do
    validate_choice_selection(effect, target_ids, :wrong_search_deck_target_count)
  end

  def validate_choice_selection(effect, target_ids, error_tag \\ :wrong_effect_target_count) do
    with :ok <-
           require_count_range(
             target_ids,
             min_count(effect),
             max_count(effect),
             error_tag
           ),
         :ok <- require_unique_ids(target_ids) do
      {:ok, target_ids}
    end
  end

  defp maybe_auto_resolve_choice(effect) do
    if requires_choice?(effect), do: :missing, else: {:ok, []}
  end

  defp min_count(%{params: %{min_count: count}}), do: count
  defp min_count(%{params: %{count: count}}), do: count
  defp min_count(_effect), do: 1

  defp max_count(%{params: %{max_count: count}}), do: count
  defp max_count(%{params: %{count: count}}), do: count
  defp max_count(_effect), do: 1

  defp require_count_range(values, min_count, max_count, error_tag) do
    count = length(values)

    if count >= min_count and count <= max_count do
      :ok
    else
      {:error, {error_tag, count, min_count, max_count}}
    end
  end

  defp require_unique_ids(ids) do
    if length(Enum.uniq(ids)) == length(ids) do
      :ok
    else
      {:error, :duplicate_card_instance_ids}
    end
  end
end
