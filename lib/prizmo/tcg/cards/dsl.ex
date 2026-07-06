defmodule Prizmo.Tcg.Cards.DSL do
  @moduledoc """
  Compile-time DSL for executable card-behavior overlays.

  Static card facts stay in `Prizmo.Tcg.Cards.Metadata`. This DSL only records
  authored behavior entries/tags and validates that referenced cards, attacks,
  and Abilities exist in the committed TCGdex cache.
  """

  alias Prizmo.Tcg.Cards.Metadata

  @supported_tags [:future, :tera]

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__), only: [card: 2]

      Module.register_attribute(__MODULE__, :behavior_cards, accumulate: true)

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro card(card_id, do: block) do
    caller = __CALLER__
    entries = parse_card!(card_id, block, caller)

    quote bind_quoted: [card_id: card_id, entries: Macro.escape(entries)] do
      @behavior_cards {card_id, entries}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @behavior_manifest Prizmo.Tcg.Cards.DSL.build_manifest(@behavior_cards)

      def behavior_manifest, do: @behavior_manifest

      def behavior_for(card_id), do: Map.fetch(@behavior_manifest, card_id)

      def behavior_card_ids, do: @behavior_manifest |> Map.keys() |> Enum.sort()
    end
  end

  def build_manifest(card_entries) do
    card_entries
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn {card_id, entries}, manifest ->
      card_manifest = Map.get(manifest, card_id, empty_card_manifest(card_id))

      card_manifest =
        Enum.reduce(entries, card_manifest, fn entry, card_manifest ->
          put_entry!(card_manifest, entry)
        end)

      Map.put(manifest, card_id, card_manifest)
    end)
  end

  defp parse_card!(card_id, block, caller) do
    if !(is_binary(card_id) and String.trim(card_id) != "") do
      raise ArgumentError, "card id must be a non-empty string"
    end

    metadata = fetch_metadata!(card_id)

    block
    |> block_expressions()
    |> Enum.map(&parse_entry!(&1, card_id, metadata, caller))
  end

  defp fetch_metadata!(card_id) do
    case Metadata.fetch(card_id) do
      {:ok, metadata} ->
        metadata

      {:error, reason} ->
        raise ArgumentError,
              "card #{inspect(card_id)} cannot declare behavior without cached metadata: #{inspect(reason)}"
    end
  end

  defp block_expressions({:__block__, _meta, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp parse_entry!({:attack, meta, [attack_id]}, card_id, metadata, caller) do
    parse_attack!(attack_id, [], meta, card_id, metadata, caller)
  end

  defp parse_entry!({:attack, meta, [attack_id, opts]}, card_id, metadata, caller) do
    parse_attack!(attack_id, opts, meta, card_id, metadata, caller)
  end

  defp parse_entry!({:ability, meta, [ability_id, opts]}, card_id, metadata, caller) do
    id = literal_id!(ability_id, :ability, caller, meta)
    metadata_ability = Map.fetch!(metadata.abilities, Atom.to_string(id))
    overlay = literal_options!(opts, caller, meta)

    validate_executable_effect!(overlay, :ability, card_id, id, metadata_ability.raw_effect)

    %{
      family: :ability,
      id: id,
      metadata_id: Atom.to_string(id),
      name: metadata_ability.name,
      overlay: overlay,
      source: source(caller, meta)
    }
  rescue
    KeyError ->
      raise ArgumentError,
            "card #{card_id} has no cached Ability #{inspect(Macro.to_string(ability_id))}"
  end

  defp parse_entry!({:card_effect, meta, [opts]}, card_id, metadata, caller) do
    overlay = literal_options!(opts, caller, meta)

    validate_executable_effect!(overlay, :card_effect, card_id, :card_effect, metadata.raw_effect)

    %{
      family: :card_effect,
      id: :card_effect,
      metadata_id: nil,
      name: metadata.name,
      overlay: overlay,
      source: source(caller, meta)
    }
  end

  defp parse_entry!({:tag, meta, [tag]}, card_id, metadata, caller) do
    tag = literal_id!(tag, :tag, caller, meta)
    validate_tag!(tag, card_id)

    %{
      family: :tag,
      id: tag,
      metadata_id: nil,
      name: metadata.name,
      overlay: %{},
      source: source(caller, meta)
    }
  end

  defp parse_entry!(expression, card_id, _metadata, _caller) do
    raise ArgumentError,
          "unsupported behavior DSL expression for card #{card_id}: #{Macro.to_string(expression)}"
  end

  defp parse_attack!(attack_id, opts, meta, card_id, metadata, caller) do
    id = literal_id!(attack_id, :attack, caller, meta)
    metadata_attack = Map.fetch!(metadata.attacks, Atom.to_string(id))
    overlay = literal_options!(opts, caller, meta)

    validate_executable_effect!(overlay, :attack, card_id, id, metadata_attack.raw_effect)

    %{
      family: :attack,
      id: id,
      metadata_id: Atom.to_string(id),
      name: metadata_attack.name,
      overlay: overlay,
      source: source(caller, meta)
    }
  rescue
    KeyError ->
      raise ArgumentError,
            "card #{card_id} has no cached attack #{inspect(Macro.to_string(attack_id))}"
  end

  defp validate_executable_effect!(overlay, family, card_id, id, raw_effect)
       when raw_effect not in [nil, ""] do
    if !Map.has_key?(overlay, :effect) do
      raise ArgumentError,
            "#{family} #{inspect(id)} for card #{card_id} has raw printed text and must declare an executable :effect overlay"
    end
  end

  defp validate_executable_effect!(_overlay, _family, _card_id, _id, _raw_effect), do: :ok

  defp validate_tag!(tag, card_id) do
    if tag in @supported_tags do
      :ok
    else
      raise ArgumentError,
            "unsupported card tag #{inspect(tag)} for card #{card_id}; supported tags: #{inspect(@supported_tags)}"
    end
  end

  defp literal_id!(value, family, caller, meta) do
    case literal!(value, caller, meta) do
      id when is_atom(id) and not is_nil(id) ->
        id

      other ->
        raise ArgumentError, "#{family} id must be an atom, got: #{inspect(other)}"
    end
  end

  defp literal_options!(opts, caller, meta) do
    case literal!(opts, caller, meta) do
      opts when is_list(opts) ->
        if !Keyword.keyword?(opts) do
          raise ArgumentError, "behavior options must be a keyword list"
        end

        Map.new(opts)

      other ->
        raise ArgumentError, "behavior options must be a keyword list, got: #{inspect(other)}"
    end
  end

  defp literal!(value, _caller, _meta)
       when is_binary(value) or is_atom(value) or is_boolean(value) or is_integer(value) or
              is_float(value) or
              is_nil(value) do
    value
  end

  defp literal!({:%{}, _meta, pairs}, caller, parent_meta) do
    Map.new(pairs, fn {key, value} ->
      {literal!(key, caller, parent_meta), literal!(value, caller, parent_meta)}
    end)
  end

  defp literal!({:{}, _meta, values}, caller, parent_meta) do
    values
    |> Enum.map(&literal!(&1, caller, parent_meta))
    |> List.to_tuple()
  end

  defp literal!({:-, _meta, [value]}, _caller, _parent_meta) when is_integer(value), do: -value

  defp literal!(values, caller, parent_meta) when is_list(values) do
    Enum.map(values, fn
      {key, value} when is_atom(key) -> {key, literal!(value, caller, parent_meta)}
      value -> literal!(value, caller, parent_meta)
    end)
  end

  defp literal!(value, caller, meta) do
    raise ArgumentError,
          "behavior DSL only accepts literal values at #{caller.file}:#{Keyword.get(meta, :line)}, got: #{Macro.to_string(value)}"
  end

  defp source(caller, meta) do
    %{
      file: caller.file,
      line: Keyword.get(meta, :line),
      module: caller.module
    }
  end

  defp empty_card_manifest(card_id) do
    %{
      card_id: card_id,
      attacks: %{},
      abilities: %{},
      card_effects: [],
      tags: []
    }
  end

  defp put_entry!(card_manifest, %{family: :attack} = entry) do
    put_nested_entry!(card_manifest, :attacks, entry)
  end

  defp put_entry!(card_manifest, %{family: :ability} = entry) do
    put_nested_entry!(card_manifest, :abilities, entry)
  end

  defp put_entry!(card_manifest, %{family: :card_effect} = entry) do
    %{card_manifest | card_effects: [entry | card_manifest.card_effects]}
  end

  defp put_entry!(card_manifest, %{family: :tag, id: tag}) do
    if tag in card_manifest.tags do
      raise ArgumentError, "duplicate card tag #{inspect(tag)} for card #{card_manifest.card_id}"
    end

    %{card_manifest | tags: [tag | card_manifest.tags]}
  end

  defp put_nested_entry!(card_manifest, field, entry) do
    entries = Map.fetch!(card_manifest, field)

    if Map.has_key?(entries, entry.id) do
      raise ArgumentError,
            "duplicate #{entry.family} #{inspect(entry.id)} behavior for card #{card_manifest.card_id}"
    end

    Map.put(card_manifest, field, Map.put(entries, entry.id, entry))
  end
end
