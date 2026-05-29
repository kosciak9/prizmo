defmodule Prizmo.TcgEngine.CostRunner do
  @moduledoc false

  alias Prizmo.TcgEngine.ChoiceValidator

  def first_cost(definition) do
    case definition.costs do
      [cost] -> {:ok, cost}
      [] -> {:error, :missing_cost_definition}
      costs -> {:error, {:multiple_costs_not_supported_yet, Enum.map(costs, & &1.key)}}
    end
  end

  def selected_choice(choices, cost), do: ChoiceValidator.fetch_choice(choices, cost.key)

  def validate_discard_from_hand_selection(cost, action_card_id, discard_ids) do
    with :ok <-
           require_exact_count(
             discard_ids,
             Map.fetch!(cost.params, :count),
             :wrong_discard_cost_count
           ),
         :ok <- require_unique_ids(discard_ids) do
      require_id_not_in(action_card_id, discard_ids)
    end
  end

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

  defp require_id_not_in(id, ids) do
    if id in ids do
      {:error, :action_card_cannot_pay_own_discard_cost}
    else
      :ok
    end
  end
end
