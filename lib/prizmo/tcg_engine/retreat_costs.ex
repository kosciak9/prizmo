defmodule Prizmo.TcgEngine.RetreatCosts do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardMetadataRequirements
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.ToolEffects

  def effective_retreat_cost(game_id, %CardInstance{} = active_card) when is_binary(game_id) do
    with {:ok, details} <- effective_retreat_cost_details(game_id, active_card) do
      {:ok, details.effective}
    end
  end

  def effective_retreat_cost(%CardInstance{} = active_card, attached_cards)
      when is_list(attached_cards) do
    with {:ok, details} <- effective_retreat_cost_details(active_card, attached_cards) do
      {:ok, details.effective}
    end
  end

  def effective_retreat_cost_details(game_id, %CardInstance{} = active_card)
      when is_binary(game_id) do
    with {:ok, attached_cards} <- CardStore.attached_cards(game_id, active_card.id) do
      effective_retreat_cost_details(active_card, attached_cards)
    end
  end

  def effective_retreat_cost_details(%CardInstance{} = active_card, attached_cards)
      when is_list(attached_cards) do
    with {:ok, printed_cost} <- CardMetadataRequirements.retreat_cost(active_card.card_id) do
      reductions = ToolEffects.retreat_cost_reductions(attached_cards)
      reduction = reductions |> Enum.map(& &1.amount) |> Enum.sum() |> min(printed_cost)

      {:ok,
       %{
         effective: max(printed_cost - reduction, 0),
         printed: printed_cost,
         reduction: reduction,
         reduction_card_instance_ids: Enum.map(reductions, & &1.card_instance_id)
       }}
    end
  end
end
