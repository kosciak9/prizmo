defmodule Prizmo.TcgEngine.CardCatalog do
  @moduledoc false

  alias Prizmo.Tcg.Cards.Metadata
  alias Prizmo.Tcg.Data.TCGdex
  alias Prizmo.TcgEngine.AttackEffects

  @energy_name_types %{
    "Colorless" => :colorless,
    "Darkness" => :darkness,
    "Dragon" => :dragon,
    "Fairy" => :fairy,
    "Fighting" => :fighting,
    "Fire" => :fire,
    "Grass" => :grass,
    "Lightning" => :lightning,
    "Metal" => :metal,
    "Psychic" => :psychic,
    "Water" => :water
  }

  @energy_symbol_types %{
    "C" => :colorless,
    "D" => :darkness,
    "F" => :fighting,
    "G" => :grass,
    "L" => :lightning,
    "M" => :metal,
    "P" => :psychic,
    "R" => :fire,
    "W" => :water
  }

  @behavior_modules [
    Prizmo.Tcg.Cards.Behaviors.ASC,
    Prizmo.Tcg.Cards.Behaviors.BLK,
    Prizmo.Tcg.Cards.Behaviors.CRI,
    Prizmo.Tcg.Cards.Behaviors.DRI,
    Prizmo.Tcg.Cards.Behaviors.JTG,
    Prizmo.Tcg.Cards.Behaviors.MEG,
    Prizmo.Tcg.Cards.Behaviors.PFL,
    Prizmo.Tcg.Cards.Behaviors.POR,
    Prizmo.Tcg.Cards.Behaviors.PRE,
    Prizmo.Tcg.Cards.Behaviors.SCR,
    Prizmo.Tcg.Cards.Behaviors.SFA,
    Prizmo.Tcg.Cards.Behaviors.SSP,
    Prizmo.Tcg.Cards.Behaviors.SVP,
    Prizmo.Tcg.Cards.Behaviors.SVI,
    Prizmo.Tcg.Cards.Behaviors.TEF,
    Prizmo.Tcg.Cards.Behaviors.TWM,
    Prizmo.Tcg.Cards.Behaviors.WHT
  ]

  @behaviors @behavior_modules
             |> Enum.flat_map(& &1.behavior_manifest())
             |> Map.new()

  def fetch(card_id) do
    with {:ok, metadata} <- Metadata.fetch(card_id) do
      {:ok,
       metadata |> metadata_card() |> apply_behavior_overlay(Map.get(@behaviors, card_id, %{}))}
    end
  end

  def fetch!(card_id) do
    case fetch(card_id) do
      {:ok, card} -> card
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  def basic_pokemon?(card_id) do
    match?({:ok, %{supertype: :pokemon, stage: :basic}}, fetch(card_id))
  end

  def stage_2_evolves_from_basic?(stage_2_card_id, basic_card_id) do
    with {:ok, %{supertype: :pokemon, stage: :stage_2, evolves_from: stage_1_name}}
         when is_binary(stage_1_name) <- fetch(stage_2_card_id),
         {:ok, %{supertype: :pokemon, stage: :basic, id: basic_id, name: basic_name}}
         when is_binary(basic_name) <- fetch(basic_card_id) do
      stage_1_name
      |> stage_1_cards_by_name()
      |> Enum.any?(&(&1.evolves_from in [basic_name, basic_id]))
    else
      _other -> false
    end
  end

  def fetch_attack(card_id, attack_id) do
    with {:ok, %{attacks: attacks}} <- fetch(card_id),
         {:ok, attack_id} <- find_attack_id(attacks, attack_id),
         {:ok, attack} <- Map.fetch(attacks, attack_id),
         :ok <- require_executable_attack(card_id, attack_id, attack) do
      {:ok, Map.put(attack, :id, attack_id)}
    else
      :error -> {:error, {:unsupported_attack, card_id, attack_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_executable_attacks(card_id) do
    with {:ok, %{attacks: attacks}} <- fetch(card_id) do
      attacks
      |> Map.keys()
      |> Enum.sort_by(&Atom.to_string/1)
      |> Enum.map(&fetch_attack(card_id, &1))
      |> collect_results()
    end
  end

  def tera_pokemon?(card_id) when is_binary(card_id) do
    match?({:ok, %{supertype: :pokemon, tera?: true}}, fetch(card_id))
  end

  def tera_pokemon?(_card_id), do: false

  def supported_card_ids do
    @behaviors
    |> Map.keys()
    |> Enum.sort()
  end

  defp metadata_card(%Metadata{} = metadata) do
    %{
      abilities: catalog_abilities(metadata.abilities),
      ace_spec?: metadata.ace_spec?,
      attacks: catalog_attacks(metadata.attacks),
      category: metadata.category,
      energy_type: catalog_energy_type(metadata),
      evolves_from: metadata.evolves_from,
      evolves_from_name: metadata.evolves_from,
      hp: metadata.hp,
      id: metadata.id,
      image: metadata.image,
      legal: metadata.legal,
      name: metadata.name,
      raw_effect: metadata.raw_effect,
      regulation_mark: metadata.regulation_mark,
      resistance: first_resistance(metadata.resistances),
      resistances: metadata.resistances,
      retreat_cost: metadata.retreat_cost,
      retreat_count: metadata.retreat_count,
      rule_box?: metadata.rule_box?,
      rarity: metadata.rarity,
      set: metadata.set,
      stage: metadata.stage,
      suffix: metadata.suffix,
      supertype: metadata.category,
      tags: [],
      tera?: false,
      tcgdex_energy_type: metadata.energy_type,
      tcgdex_id: metadata.tcgdex_id,
      trainer_type: metadata.trainer_type,
      type: primary_type(metadata),
      types: metadata.types,
      weakness: first_weakness(metadata.weaknesses),
      weaknesses: metadata.weaknesses
    }
  end

  defp apply_behavior_overlay(card, behavior) do
    card
    |> merge_attack_overlays(behavior |> Map.get(:attacks, %{}) |> behavior_entry_overlays())
    |> merge_ability_overlays(behavior |> Map.get(:abilities, %{}) |> behavior_entry_overlays())
    |> merge_card_tags(Map.get(behavior, :tags, []))
    |> maybe_put_overlay(:effect, card_effect(behavior))
    |> maybe_put_overlay(:provides, inferred_provides(card))
  end

  defp merge_card_tags(card, tags) do
    tags = Enum.uniq(card.tags ++ tags)

    %{card | tags: tags, tera?: :tera in tags}
  end

  defp behavior_entry_overlays(entries) do
    Map.new(entries, fn {id, entry} -> {id, entry.overlay} end)
  end

  defp card_effect(%{card_effects: [%{overlay: %{effect: effect}} | _effects]}), do: effect
  defp card_effect(_behavior), do: nil

  defp merge_attack_overlays(card, overlays) do
    attacks = merge_entry_overlays(card.attacks, overlays, &executable_attack_fields/2)
    %{card | attacks: attacks}
  end

  defp merge_ability_overlays(card, overlays) do
    abilities =
      merge_entry_overlays(card.abilities, overlays, fn _entry, overlay ->
        Map.take(overlay, [:effect])
      end)

    %{card | abilities: abilities}
  end

  defp merge_entry_overlays(entries, overlays, fields_fun) do
    Enum.reduce(overlays, entries, fn {id, overlay}, entries ->
      entry = Map.get(entries, id, %{name: Map.get(overlay, :name)})
      Map.put(entries, id, Map.merge(entry, fields_fun.(entry, overlay)))
    end)
  end

  defp executable_attack_fields(entry, overlay) do
    overlay
    |> Map.take([:effect])
    |> maybe_put_executable_damage(entry, overlay)
  end

  defp maybe_put_executable_damage(fields, %{damage: damage}, %{damage: executable_damage})
       when is_integer(damage) and not is_nil(executable_damage) do
    fields
  end

  defp maybe_put_executable_damage(fields, _entry, %{damage: executable_damage})
       when is_integer(executable_damage) do
    Map.put(fields, :damage, executable_damage)
  end

  defp maybe_put_executable_damage(fields, _entry, _overlay), do: fields

  defp maybe_put_overlay(card, _field, nil), do: card
  defp maybe_put_overlay(card, field, value), do: Map.put(card, field, value)

  defp catalog_attacks(attacks) do
    Map.new(attacks, fn {id, attack} ->
      # sobelow_skip ["DOS.StringToAtom"] attack ids come from bounded compile-time card metadata.
      {String.to_atom(id),
       %{
         cost: attack.cost,
         damage: attack.damage,
         name: attack.name,
         raw_effect: attack.raw_effect
       }}
    end)
  end

  defp catalog_abilities(abilities) do
    Map.new(abilities, fn {id, ability} ->
      # sobelow_skip ["DOS.StringToAtom"] ability ids come from bounded compile-time card metadata.
      {String.to_atom(id),
       %{
         name: ability.name,
         raw_effect: ability.raw_effect,
         type: ability.type
       }}
    end)
  end

  defp catalog_energy_type(%Metadata{category: :energy, raw_effect: nil}), do: :basic
  defp catalog_energy_type(%Metadata{category: :energy}), do: :special
  defp catalog_energy_type(%Metadata{} = metadata), do: metadata.energy_type

  defp inferred_provides(%{supertype: :energy, energy_type: :basic, name: name}) do
    Enum.find_value(@energy_name_types, [], fn {label, type} ->
      if String.contains?(name, label), do: [type]
    end)
  end

  defp inferred_provides(%{supertype: :energy, energy_type: :special, raw_effect: raw_effect})
       when is_binary(raw_effect) do
    ~r/\bit provides \{([A-Z])\} Energy\b/i
    |> Regex.scan(raw_effect, capture: :all_but_first)
    |> Enum.map(fn [symbol] -> Map.get(@energy_symbol_types, String.upcase(symbol)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      provides -> provides
    end
  end

  defp inferred_provides(_card), do: nil

  defp stage_1_cards_by_name(stage_1_name) do
    Map.get(stage_1_evolution_index(), stage_1_name, [])
  end

  defp stage_1_evolution_index do
    key = {__MODULE__, :stage_1_evolution_index}

    case :persistent_term.get(key, :missing) do
      :missing ->
        index = load_stage_1_evolution_index()
        :persistent_term.put(key, index)
        index

      index ->
        index
    end
  end

  defp load_stage_1_evolution_index do
    TCGdex.cache_root()
    |> Path.join("cards/*.json")
    |> Path.wildcard()
    |> Enum.flat_map(&stage_1_card_from_cache_path/1)
    |> Enum.group_by(& &1.name)
  end

  defp stage_1_card_from_cache_path(path) do
    with {:ok, %{"prizmo_id" => id, "tcgdex" => card}} <- read_cached_card_payload(path),
         "Pokemon" <- Map.get(card, "category"),
         "Stage1" <- Map.get(card, "stage"),
         name when is_binary(name) <- Map.get(card, "name"),
         evolves_from when is_binary(evolves_from) <- Map.get(card, "evolveFrom") do
      [%{id: id, name: name, evolves_from: evolves_from}]
    else
      _other -> []
    end
  end

  # sobelow_skip ["Traversal.FileModule"] paths come from the repository-controlled TCGdex cache root.
  defp read_cached_card_payload(path) do
    path
    |> File.read!()
    |> Jason.decode()
  end

  defp primary_type(%Metadata{types: [type | _types]}), do: type
  defp primary_type(%Metadata{}), do: nil

  defp find_attack_id(attacks, attack_id) when is_atom(attack_id) do
    if Map.has_key?(attacks, attack_id) do
      {:ok, attack_id}
    else
      :error
    end
  end

  defp find_attack_id(attacks, attack_id) when is_binary(attack_id) do
    attacks
    |> Map.keys()
    |> Enum.find(&(Atom.to_string(&1) == attack_id))
    |> case do
      nil -> :error
      attack_id -> {:ok, attack_id}
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

  defp first_weakness([%{type: type, value: value} | _weaknesses]) do
    %{type: type, multiplier: multiplier_value(value)}
  end

  defp first_weakness(_weaknesses), do: nil

  defp first_resistance([%{type: type, value: value} | _resistances]) do
    %{type: type, value: signed_value(value)}
  end

  defp first_resistance(_resistances), do: nil

  defp multiplier_value(value) when is_integer(value), do: value

  defp multiplier_value(value) do
    case Regex.run(~r/\d+/, to_string(value)) do
      [digits] -> String.to_integer(digits)
      _none -> 2
    end
  end

  defp signed_value(value) when is_integer(value), do: value

  defp signed_value(value) do
    case Regex.run(~r/-?\d+/, to_string(value)) do
      [digits] -> String.to_integer(digits)
      _none -> 0
    end
  end

  defp require_executable_attack(card_id, attack_id, %{effect: effect}) when is_map(effect) do
    if AttackEffects.supported?(effect) do
      :ok
    else
      {:error, {:unsupported_attack_effect, card_id, attack_id, AttackEffects.type(effect)}}
    end
  end

  defp require_executable_attack(card_id, attack_id, %{raw_effect: raw_effect})
       when raw_effect not in [nil, ""] do
    {:error, {:missing_executable_attack_behavior, card_id, attack_id}}
  end

  defp require_executable_attack(_card_id, _attack_id, %{damage: damage}) when is_integer(damage),
    do: :ok

  defp require_executable_attack(card_id, attack_id, _attack),
    do: {:error, {:missing_executable_attack_behavior, card_id, attack_id}}
end
