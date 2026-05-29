defmodule Prizmo.Tcg.Cards.Metadata do
  @moduledoc """
  Normalized, offline card metadata from the committed TCGdex cache.

  TCGdex owns static card facts. This module reads cached payloads and exposes a
  Prizmo-friendly shape without adding executable attacks, abilities, or effects.
  """

  alias Prizmo.Tcg.Data.TCGdex

  defstruct ace_spec?: false,
            abilities: %{},
            attacks: %{},
            category: nil,
            energy_type: nil,
            evolves_from: nil,
            hp: nil,
            id: nil,
            image: nil,
            legal: %{},
            name: nil,
            raw_effect: nil,
            regulation_mark: nil,
            resistances: [],
            retreat_cost: [],
            retreat_count: nil,
            rule_box?: false,
            rarity: nil,
            set: %{},
            stage: nil,
            suffix: nil,
            tcgdex_id: nil,
            trainer_type: nil,
            types: [],
            weaknesses: []

  @doc "Reads and normalizes cached metadata for a Prizmo card ID."
  def fetch(card_id, opts \\ []) do
    path = TCGdex.card_cache_path(card_id, opts)

    if File.exists?(path) do
      {:ok, path |> read_json!() |> normalize!()}
    else
      {:error, {:metadata_not_cached, card_id}}
    end
  end

  @doc "Reads cached metadata or raises when it is absent/invalid."
  def fetch!(card_id, opts \\ []) do
    case fetch(card_id, opts) do
      {:ok, metadata} ->
        metadata

      {:error, reason} ->
        raise ArgumentError, inspect(reason)
    end
  end

  @doc "Returns true when a Prizmo card ID has a committed TCGdex cache entry."
  def cached?(card_id, opts \\ []) do
    card_id
    |> TCGdex.card_cache_path(opts)
    |> File.exists?()
  end

  defp normalize!(%{"prizmo_id" => prizmo_id, "tcgdex_id" => tcgdex_id, "tcgdex" => card}) do
    suffix = Map.get(card, "suffix")
    rarity = Map.get(card, "rarity")

    %__MODULE__{
      ace_spec?: ace_spec?(rarity),
      abilities: normalize_named_entries(Map.get(card, "abilities"), &normalize_ability/1),
      attacks: normalize_named_entries(Map.get(card, "attacks"), &normalize_attack/1),
      category: normalize_atom(Map.fetch!(card, "category")),
      energy_type: normalize_atom(Map.get(card, "energyType")),
      evolves_from: Map.get(card, "evolveFrom"),
      hp: Map.get(card, "hp"),
      id: prizmo_id,
      image: Map.get(card, "image"),
      legal: normalize_legal(Map.get(card, "legal")),
      name: Map.fetch!(card, "name"),
      raw_effect: Map.get(card, "effect"),
      regulation_mark: Map.get(card, "regulationMark"),
      resistances: normalize_type_values(Map.get(card, "resistances")),
      retreat_count: Map.get(card, "retreat"),
      retreat_cost: retreat_cost(Map.get(card, "retreat")),
      rule_box?: rule_box?(suffix),
      rarity: rarity,
      set: normalize_set(Map.get(card, "set")),
      stage: normalize_stage(Map.get(card, "stage")),
      suffix: suffix,
      tcgdex_id: tcgdex_id,
      trainer_type: normalize_atom(Map.get(card, "trainerType")),
      types: normalize_types(Map.get(card, "types")),
      weaknesses: normalize_type_values(Map.get(card, "weaknesses"))
    }
  end

  defp normalize!(payload) do
    raise ArgumentError, "invalid TCGdex cache payload: #{inspect(payload)}"
  end

  defp normalize_named_entries(nil, _normalizer), do: %{}

  defp normalize_named_entries(entries, normalizer) do
    entries
    |> Enum.map(normalizer)
    |> Map.new(fn entry -> {entry.id, entry} end)
  end

  defp normalize_attack(%{"name" => name} = attack) do
    %{
      cost: normalize_types(Map.get(attack, "cost")),
      damage: Map.get(attack, "damage"),
      id: slug(name),
      name: name,
      raw_effect: Map.get(attack, "effect")
    }
  end

  defp normalize_ability(%{"name" => name} = ability) do
    %{
      id: slug(name),
      name: name,
      raw_effect: Map.get(ability, "effect"),
      type: normalize_atom(Map.get(ability, "type"))
    }
  end

  defp normalize_stage(nil), do: nil
  defp normalize_stage("Basic"), do: :basic
  defp normalize_stage("Stage1"), do: :stage_1
  defp normalize_stage("Stage2"), do: :stage_2
  defp normalize_stage(stage), do: normalize_atom(stage)

  defp normalize_types(nil), do: []
  defp normalize_types(types), do: Enum.map(types, &normalize_atom/1)

  defp normalize_type_values(nil), do: []

  defp normalize_type_values(entries) do
    Enum.map(entries, fn entry ->
      %{
        type: normalize_atom(Map.get(entry, "type")),
        value: Map.get(entry, "value")
      }
    end)
  end

  defp normalize_legal(nil), do: %{}

  defp normalize_legal(legal) do
    Map.new(legal, fn {format, legal?} -> {normalize_atom(format), legal?} end)
  end

  defp normalize_set(nil), do: %{}

  defp normalize_set(set) do
    %{
      card_count: Map.get(set, "cardCount"),
      id: Map.get(set, "id"),
      logo: Map.get(set, "logo"),
      name: Map.get(set, "name"),
      symbol: Map.get(set, "symbol")
    }
  end

  defp retreat_cost(nil), do: []
  defp retreat_cost(count), do: List.duplicate(:colorless, count)

  defp rule_box?(nil), do: false
  defp rule_box?(suffix), do: suffix in ["ex", "EX", "GX", "V", "VMAX", "VSTAR"]

  defp ace_spec?(nil), do: false
  defp ace_spec?(rarity), do: String.contains?(rarity, "ACE SPEC")

  defp normalize_atom(nil), do: nil

  # sobelow_skip ["DOS.StringToAtom"] card metadata is local curated TCGdex/import data with bounded values.
  defp normalize_atom(value) when is_binary(value) do
    value
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.trim("_")
    |> String.to_atom()
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  # sobelow_skip ["Traversal.FileModule"] paths are built from repository-controlled card metadata locations.
  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
