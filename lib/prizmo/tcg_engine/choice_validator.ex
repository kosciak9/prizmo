defmodule Prizmo.TcgEngine.ChoiceValidator do
  @moduledoc false

  def normalize_payload(opts, definition) when is_map(opts) do
    raw_choices = Map.get(opts, :choices, Map.get(opts, "choices", %{})) || %{}
    known_keys = known_choice_keys(definition)

    Enum.reduce_while(raw_choices, {:ok, %{}}, fn {raw_key, raw_value}, {:ok, acc} ->
      case normalize_key(raw_key, known_keys) do
        {:ok, key} ->
          case normalize_choice(raw_value) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def normalize_choice(value) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      {:ok, value}
    else
      {:error, :invalid_choice_payload}
    end
  end

  def normalize_choice(value) when is_binary(value), do: {:ok, [value]}
  def normalize_choice(_value), do: {:error, :invalid_choice_payload}

  def fetch_choice(choices, key) do
    case Map.fetch(choices, key) do
      {:ok, value} -> {:ok, value}
      :error -> :missing
    end
  end

  def put_choice(choices, choice_key, submitted_choice) when is_binary(choice_key) do
    Map.put(choices, String.to_existing_atom(choice_key), submitted_choice)
  end

  def put_choice(choices, choice_key, submitted_choice) when is_atom(choice_key) do
    Map.put(choices, choice_key, submitted_choice)
  end

  def stringify_keys(choices) do
    Map.new(choices, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  def from_pending_state(state) do
    state
    |> Map.get("choices", %{})
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  def count_for(definition, choice_key) do
    definition
    |> choice_steps()
    |> Enum.find(&(&1.key == choice_key))
    |> case do
      %{params: %{min_count: count}} -> count
      %{params: %{count: count}} -> count
      _other -> 1
    end
  end

  def max_count_for(definition, choice_key) do
    definition
    |> choice_steps()
    |> Enum.find(&(&1.key == choice_key))
    |> case do
      %{params: %{max_count: count}} -> count
      %{params: %{count: count}} -> count
      _other -> 1
    end
  end

  def known_choice_keys(definition), do: Enum.map(choice_steps(definition), & &1.key)

  defp normalize_key(key, known_keys) when is_atom(key) do
    if key in known_keys, do: {:ok, key}, else: {:error, {:unknown_choice_key, key}}
  end

  defp normalize_key(key, known_keys) when is_binary(key) do
    case Enum.find(known_keys, &(Atom.to_string(&1) == key)) do
      nil -> {:error, {:unknown_choice_key, key}}
      known_key -> {:ok, known_key}
    end
  end

  defp normalize_key(key, _known_keys), do: {:error, {:invalid_choice_key, key}}

  defp choice_steps(definition), do: definition.costs ++ definition.effects
end
