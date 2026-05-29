defmodule Prizmo.TcgEngine.EffectRunner do
  @moduledoc false

  alias Prizmo.TcgEngine.ChoiceValidator

  def first_effect(definition) do
    case definition.effects do
      [effect] -> {:ok, effect}
      [] -> {:error, :missing_effect_definition}
      effects -> {:error, {:multiple_effects_not_supported_yet, Enum.map(effects, & &1.key)}}
    end
  end

  def selected_choice(choices, effect), do: ChoiceValidator.fetch_choice(choices, effect.key)

  def validate_search_deck_selection(effect, target_ids) do
    with :ok <-
           require_exact_count(
             target_ids,
             Map.fetch!(effect.params, :count),
             :wrong_search_deck_target_count
           ),
         :ok <- require_unique_ids(target_ids) do
      one_target(target_ids)
    end
  end

  defp one_target([target_id]), do: {:ok, target_id}
  defp one_target([]), do: {:error, :missing_search_deck_target}
  defp one_target(_targets), do: {:error, :too_many_search_deck_targets}

  defp require_exact_count(values, count, error_tag) do
    if length(values) == count do
      :ok
    else
      {:error, {error_tag, length(values)}}
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
