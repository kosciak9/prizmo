defmodule Prizmo.Tcg.CardCoverage do
  @moduledoc """
  Generic card-level coverage classification for roadmap corpus work.

  This mirrors the same broad support buckets used by the knowledge-base
  roadmap so live corpus reports can distinguish supported, generic, partial,
  and still unimplemented cards without spinning up the whole play surface.
  """

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.StadiumEffects
  alias Prizmo.TcgEngine.ToolEffects

  @type coverage_status :: :supported | :generic_supported | :partial | :unimplemented

  @type summary :: %{
          coverage_status: coverage_status(),
          rules_status: atom(),
          rules_label: String.t(),
          rules_note: String.t(),
          executable_attack_count: non_neg_integer(),
          unsupported_attack_count: non_neg_integer(),
          unsupported_ability_count: non_neg_integer()
        }

  @doc "Returns a coverage summary for a single card id."
  @spec summarize(String.t()) :: summary()
  def summarize(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> do_summarize(card_id, card)
      {:error, _reason} -> unknown_summary()
    end
  end

  defp do_summarize(_card_id, %{id: nil}), do: unknown_summary()

  defp do_summarize(card_id, %{supertype: :trainer} = card) do
    case EngineCardRegistry.fetch(card_id) do
      {:ok, %{play_window: :action_window}} ->
        summary(
          :engine_defined,
          "Engine-defined",
          "This Trainer has authored engine behavior and appears as a Play action when costs and timing are legal."
        )

      {:ok, _definition} ->
        summary(
          :partial,
          "Timing pending",
          "This Trainer has authored behavior, but its play window is not exposed in the current action surface."
        )

      {:error, _reason} ->
        generic_trainer_summary(card)
    end
  end

  defp do_summarize(_card_id, %{supertype: :energy, energy_type: :basic}) do
    summary(
      :generic,
      "Generic Energy",
      "Basic Energy can attach through the generic engine action."
    )
  end

  defp do_summarize(_card_id, %{supertype: :energy, energy_type: :special} = card) do
    if supported_special_energy?(card) do
      summary(
        :engine_defined,
        "Engine-defined Energy",
        "This Special Energy provides its supported Energy type and enforces its authored engine text."
      )
    else
      summary(
        :partial,
        "Special text pending",
        "This Energy can attach through the generic engine action; special card text is not executable yet."
      )
    end
  end

  defp do_summarize(_card_id, %{supertype: :energy}) do
    summary(
      :partial,
      "Special text pending",
      "This Energy can attach through the generic engine action; special card text is not executable yet."
    )
  end

  defp do_summarize(card_id, %{supertype: :pokemon} = card) do
    %{executable: executable_attack_count, unsupported: unsupported_attack_count} =
      attack_support_counts(card_id, card)

    unsupported_ability_count = unsupported_ability_count(card)

    cond do
      unsupported_attack_count == 0 and unsupported_ability_count == 0 and
          executable_attack_count > 0 ->
        summary(
          :engine_defined,
          "Executable attacks",
          "This Pokémon has executable attacks for the current engine slice.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      executable_attack_count > 0 ->
        summary(
          :partial,
          "Partial attacks",
          "Some attacks are executable; unsupported attacks or abilities are omitted from legal actions.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      unsupported_attack_count > 0 or unsupported_ability_count > 0 ->
        summary(
          :unsupported,
          "Card text pending",
          "Generic board actions can still use this Pokémon, but attacks or abilities are not executable yet.",
          executable_attack_count,
          unsupported_attack_count,
          unsupported_ability_count
        )

      true ->
        summary(
          :generic,
          "Generic Pokémon",
          "Setup, Bench, evolution, retreat, attachments, and other generic board actions can use this Pokémon."
        )
    end
  end

  defp do_summarize(_card_id, _card), do: unknown_summary()

  defp unknown_summary do
    summary(
      :unknown,
      "Catalog missing",
      "This card could not be resolved in the committed catalog."
    )
  end

  defp generic_trainer_summary(%{trainer_type: :stadium} = card) do
    if StadiumEffects.supported_stadium?(card) do
      summary(
        :engine_defined,
        "Engine-defined Stadium",
        "This Stadium can be played generically and its authored Stadium text is enforced by the engine."
      )
    else
      summary(
        :partial,
        "Generic Stadium",
        "This Stadium can be played through the generic engine action; printed Stadium text may still be pending."
      )
    end
  end

  defp generic_trainer_summary(%{trainer_type: :tool} = card) do
    if ToolEffects.supported_tool?(card) do
      summary(
        :engine_defined,
        "Engine-defined Tool",
        "This Tool attaches generically and its authored Tool text is enforced by the engine."
      )
    else
      summary(
        :partial,
        "Generic Tool",
        "This Tool can attach through the generic engine action; printed Tool text may still be pending."
      )
    end
  end

  defp generic_trainer_summary(card) do
    summary(
      :unsupported,
      unsupported_trainer_label(card),
      "Known catalog card; Trainer text has no executable engine behavior yet, so no Play button appears."
    )
  end

  defp unsupported_trainer_label(%{trainer_type: trainer_type})
       when trainer_type not in [nil, :unknown] do
    "Unsupported #{trainer_type |> Atom.to_string() |> String.capitalize()}"
  end

  defp unsupported_trainer_label(_card), do: "Unsupported Trainer"

  defp summary(status, label, note) do
    summary(status, label, note, 0, 0, 0)
  end

  defp summary(
         rules_status,
         rules_label,
         rules_note,
         executable_attack_count,
         unsupported_attack_count,
         unsupported_ability_count
       ) do
    %{
      coverage_status: coverage_status(rules_status),
      rules_status: rules_status,
      rules_label: rules_label,
      rules_note: rules_note,
      executable_attack_count: executable_attack_count,
      unsupported_attack_count: unsupported_attack_count,
      unsupported_ability_count: unsupported_ability_count
    }
  end

  defp coverage_status(:engine_defined), do: :supported
  defp coverage_status(:generic), do: :generic_supported
  defp coverage_status(:partial), do: :partial
  defp coverage_status(:unsupported), do: :unimplemented
  defp coverage_status(:unknown), do: :unimplemented

  defp attack_support_counts(card_id, %{attacks: attacks}) when is_map(attacks) do
    Enum.reduce(attacks, %{executable: 0, unsupported: 0}, fn {attack_id, _attack}, counts ->
      case CardCatalog.fetch_attack(card_id, attack_id) do
        {:ok, _attack} -> Map.update!(counts, :executable, &(&1 + 1))
        {:error, _reason} -> Map.update!(counts, :unsupported, &(&1 + 1))
      end
    end)
  end

  defp attack_support_counts(_card_id, _card), do: %{executable: 0, unsupported: 0}

  defp unsupported_ability_count(%{abilities: abilities}) when is_map(abilities) do
    Enum.count(abilities, fn {_ability_id, ability} ->
      present_text?(Map.get(ability, :raw_effect)) and is_nil(Map.get(ability, :effect))
    end)
  end

  defp unsupported_ability_count(_card), do: 0

  defp supported_special_energy?(%{
         effect: %{
           type: :provides_every_type_when_attached_to_stage_2,
           provider_count: provider_count
         },
         provides: provides
       })
       when is_integer(provider_count) and provider_count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :provides_every_type_when_attached_to_basic},
         provides: provides
       })
       when is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :bench_basic_psychic_from_deck_when_attached_to_psychic,
           max_targets: max_targets
         },
         provides: provides
       })
       when is_integer(max_targets) and max_targets > 0 and is_list(provides) do
    :psychic in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :draw_cards_on_attach_from_hand, count: count},
         provides: provides
       })
       when is_integer(count) and count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :place_damage_counters_on_attacker_if_damaged_as_active_by_attack,
           count: count
         },
         provides: provides
       })
       when is_integer(count) and count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :prevent_opponent_attack_effects_to_attached_pokemon,
           required_attached_pokemon_type: :fighting
         },
         provides: provides
       })
       when is_list(provides) do
    :fighting in provides
  end

  defp supported_special_energy?(%{
         effect: %{
           type: :water_pokemon_special_condition_immunity_energy,
           required_attached_pokemon_type: :water
         },
         provides: provides
       })
       when is_list(provides) do
    :water in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :prevent_opponent_attack_effects_to_attached_pokemon},
         provides: provides
       })
       when is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(%{
         effect: %{type: :team_rocket_energy_attachment_and_dual_provides},
         name: "Team Rocket's Energy"
       }),
       do: true

  defp supported_special_energy?(_card), do: false

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
