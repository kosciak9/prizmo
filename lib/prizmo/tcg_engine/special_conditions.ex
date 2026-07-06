defmodule Prizmo.TcgEngine.SpecialConditions do
  @moduledoc false

  alias Prizmo.TcgEngine.CardInstance

  @special_conditions_key "special_conditions"
  @marker_backed_conditions [:poisoned]

  @spec put_condition_marker(CardInstance.t(), atom()) :: map()
  def put_condition_marker(%CardInstance{markers: markers}, condition)
      when condition in @marker_backed_conditions do
    markers
    |> normalize_markers()
    |> Map.update(@special_conditions_key, [Atom.to_string(condition)], fn conditions ->
      conditions
      |> normalize_conditions()
      |> Kernel.++([Atom.to_string(condition)])
      |> Enum.uniq()
    end)
    |> Map.delete(:special_conditions)
  end

  @spec clear_condition_markers(CardInstance.t()) :: map()
  def clear_condition_markers(%CardInstance{markers: markers}) do
    markers
    |> normalize_markers()
    |> Map.delete(@special_conditions_key)
    |> Map.delete(:special_conditions)
  end

  @spec conditions(CardInstance.t()) :: [atom()]
  def conditions(%CardInstance{status: status, markers: markers}) do
    ([status] ++ marker_conditions(markers))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec poisoned?(CardInstance.t()) :: boolean()
  def poisoned?(%CardInstance{} = card), do: :poisoned in conditions(card)

  defp marker_conditions(markers) do
    markers
    |> persisted_conditions()
    |> normalize_conditions()
    |> Enum.map(&condition_atom/1)
    |> Enum.reject(&is_nil/1)
  end

  defp persisted_conditions(markers) when is_map(markers) do
    Map.get(markers, @special_conditions_key) || Map.get(markers, :special_conditions) || []
  end

  defp persisted_conditions(_markers), do: []

  defp normalize_conditions(conditions) when is_list(conditions), do: conditions

  defp normalize_conditions(condition) when is_binary(condition) or is_atom(condition),
    do: [condition]

  defp normalize_conditions(_conditions), do: []

  defp condition_atom(condition) when condition in @marker_backed_conditions, do: condition

  defp condition_atom(condition) when is_binary(condition) do
    Enum.find(@marker_backed_conditions, &(Atom.to_string(&1) == condition))
  end

  defp condition_atom(_condition), do: nil

  defp normalize_markers(markers) when is_map(markers), do: markers
  defp normalize_markers(_markers), do: %{}
end
