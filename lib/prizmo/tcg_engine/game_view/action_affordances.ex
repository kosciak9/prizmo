defmodule Prizmo.TcgEngine.GameView.ActionAffordances do
  @moduledoc false

  alias Prizmo.TcgEngine.AttackCosts
  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.AttackLocks
  alias Prizmo.TcgEngine.AttackRequirements
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardPlay
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.RetreatLocks
  alias Prizmo.TcgEngine.Turn

  @doc "Returns action affordances visible to the current game viewer."
  def for_viewer(%Game{} = game, current_turn, players, cards, prompts, viewer_player_id)
      when is_list(players) and is_list(cards) and is_list(prompts) and
             is_binary(viewer_player_id) do
    case prompt_affordances(prompts) do
      [] ->
        case replacement_active_affordances(game, current_turn, cards, viewer_player_id) do
          [] -> action_window_affordances(game, current_turn, players, cards, viewer_player_id)
          replacement_actions -> replacement_actions
        end

      prompt_actions ->
        prompt_actions
    end
  end

  defp prompt_affordances(prompts), do: Enum.map(prompts, &prompt_affordance/1)

  defp prompt_affordance(%Prompt{} = prompt) do
    affordance(:choose_prompt, "Resolve prompt", :prompt, prompt.player_id,
      prompt_ids: [prompt.id],
      choice_keys: choice_keys(prompt),
      note: "Resolve this pending engine choice before taking another action."
    )
  end

  defp replacement_active_affordances(
         %Game{status: :in_progress},
         %Turn{status: :attack_resolving},
         cards,
         viewer_player_id
       ) do
    viewer_cards = Enum.filter(cards, &(&1.owner_player_id == viewer_player_id))

    case active_pokemon_card(viewer_cards) do
      %CardInstance{} ->
        []

      nil ->
        target_ids = viewer_cards |> bench_pokemon_cards() |> card_ids()

        if Enum.empty?(target_ids) do
          []
        else
          [
            affordance(
              :choose_replacement_active,
              "Choose replacement Active",
              :command,
              viewer_player_id,
              target_card_instance_ids: target_ids,
              note:
                "A knockout left this player without an Active Pokémon. Choose one Benched Pokémon before the attack can finish."
            )
          ]
        end
    end
  end

  defp replacement_active_affordances(_game, _current_turn, _cards, _viewer_player_id), do: []

  defp action_window_affordances(game, current_turn, players, cards, viewer_player_id) do
    if action_window_for_viewer?(game, current_turn, viewer_player_id) do
      player = Enum.find(players, &(&1.player_id == viewer_player_id))
      viewer_cards = Enum.filter(cards, &(&1.owner_player_id == viewer_player_id))

      player
      |> available_action_window_affordances(current_turn, viewer_cards, cards)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp action_window_for_viewer?(
         %Game{status: :in_progress},
         %Turn{status: :action_window, active_player_id: active_player_id},
         viewer_player_id
       ),
       do: active_player_id == viewer_player_id

  defp action_window_for_viewer?(_game, _current_turn, _viewer_player_id), do: false

  defp available_action_window_affordances(nil, _current_turn, _cards, _all_cards), do: []

  defp available_action_window_affordances(%GamePlayer{} = player, current_turn, cards, all_cards) do
    [
      play_card_affordance(player, cards),
      play_basic_to_bench_affordance(player, cards),
      attach_energy_affordance(player, cards),
      retreat_affordance(player, current_turn, cards)
    ] ++
      evolve_from_hand_affordances(player, current_turn, cards) ++
      declare_attack_affordances(player, current_turn, cards, all_cards) ++
      unsupported_card_text_affordances(player, current_turn, cards, all_cards) ++
      [
        pass_affordance(player)
      ]
  end

  defp play_card_affordance(%GamePlayer{} = player, cards) do
    source_ids =
      cards
      |> hand_cards()
      |> Enum.filter(&engine_playable_card?(&1, cards))
      |> card_ids()

    if Enum.empty?(source_ids) do
      nil
    else
      affordance(:play_card, "Play engine-defined card", :command, player.player_id,
        source_card_instance_ids: source_ids,
        note: "Cards with engine-owned behavior can start costs, effects, or prompts."
      )
    end
  end

  defp play_basic_to_bench_affordance(%GamePlayer{} = player, cards) do
    source_ids =
      cards
      |> hand_cards()
      |> Enum.filter(&basic_pokemon?/1)
      |> card_ids()

    if Enum.empty?(source_ids) or bench_full?(cards) do
      nil
    else
      affordance(:play_basic_to_bench, "Bench Basic Pokémon", :command, player.player_id,
        source_card_instance_ids: source_ids,
        note: "Choose one Basic Pokémon from hand for the next Bench slot."
      )
    end
  end

  defp attach_energy_affordance(%GamePlayer{energy_attached_this_turn?: true}, _cards), do: nil

  defp attach_energy_affordance(%GamePlayer{} = player, cards) do
    source_ids =
      cards
      |> hand_cards()
      |> Enum.filter(&energy_card?/1)
      |> card_ids()

    target_ids = cards |> in_play_pokemon_cards() |> card_ids()

    if Enum.empty?(source_ids) or Enum.empty?(target_ids) do
      nil
    else
      affordance(:attach_energy, "Attach Energy", :command, player.player_id,
        source_card_instance_ids: source_ids,
        target_card_instance_ids: target_ids,
        note: "Choose one Energy from hand and one of your Pokémon in play."
      )
    end
  end

  defp evolve_from_hand_affordances(
         %GamePlayer{} = player,
         %Turn{turn_number: turn_number},
         cards
       )
       when turn_number > 1 do
    evolution_cards = cards |> hand_cards() |> Enum.filter(&evolution_pokemon?/1)
    targets = Enum.filter(in_play_pokemon_cards(cards), &can_evolve_target?(&1, turn_number))

    for evolution_card <- evolution_cards,
        target_card <- targets,
        evolves_from?(evolution_card, target_card) do
      affordance(:evolve_from_hand, "Evolve Pokémon", :command, player.player_id,
        source_card_instance_ids: [evolution_card.id],
        target_card_instance_ids: [target_card.id],
        note:
          "Use a valid evolution card from hand on a Pokémon that entered play on an earlier turn."
      )
    end
  end

  defp evolve_from_hand_affordances(_player, _current_turn, _cards), do: []

  defp retreat_affordance(%GamePlayer{retreated_this_turn?: true}, _current_turn, _cards), do: nil

  defp retreat_affordance(%GamePlayer{} = player, %Turn{} = current_turn, cards) do
    with %CardInstance{} = active_card <- active_pokemon_card(cards),
         false <- blocked_retreat_status?(active_card),
         false <- RetreatLocks.blocked_this_turn?(active_card, current_turn),
         target_ids when target_ids != [] <- cards |> bench_pokemon_cards() |> card_ids(),
         {:ok, retreat_cost} <- retreat_cost(active_card),
         source_ids = cards |> active_attached_energy_cards(active_card.id) |> card_ids(),
         true <- length(source_ids) >= retreat_cost do
      affordance(:retreat, "Retreat Active Pokémon", :command, player.player_id,
        source_card_instance_ids: source_ids,
        target_card_instance_ids: target_ids,
        required_source_count: retreat_cost,
        choice_keys: ["retreat_energy"],
        note: retreat_note(retreat_cost)
      )
    else
      _other -> nil
    end
  end

  defp declare_attack_affordances(
         %GamePlayer{} = player,
         %Turn{} = current_turn,
         cards,
         all_cards
       ) do
    with %CardInstance{} = active_card <- active_pokemon_card(cards),
         false <- blocked_attack_status?(active_card),
         false <- AttackLocks.blocked_this_turn?(active_card, current_turn),
         true <-
           AttackRequirements.attack_restrictions_met?(active_card, in_play_pokemon_cards(cards)),
         %CardInstance{} = defender_card <-
           opponent_active_pokemon_card(all_cards, player.player_id),
         {:ok, %{attacks: attacks}} <- CardCatalog.fetch(active_card.card_id) do
      attached_cards = attached_cards_for(cards, active_card.id)

      attacks
      |> Enum.sort_by(fn {attack_id, _attack} -> Atom.to_string(attack_id) end)
      |> Enum.flat_map(fn {attack_id, attack} ->
        maybe_attack_affordance(
          player,
          active_card,
          defender_card,
          attached_cards,
          attack_id,
          attack
        )
      end)
    else
      _other -> []
    end
  end

  defp pass_affordance(%GamePlayer{} = player) do
    affordance(:pass, "Pass", :command, player.player_id,
      note: "Pass to end this turn and let the engine start the next player's turn."
    )
  end

  defp affordance(key, label, kind, player_id, opts) do
    %{
      key: Atom.to_string(key),
      label: label,
      kind: Atom.to_string(kind),
      player_id: player_id,
      source_card_instance_ids: Keyword.get(opts, :source_card_instance_ids, []),
      target_card_instance_ids: Keyword.get(opts, :target_card_instance_ids, []),
      required_source_count: Keyword.get(opts, :required_source_count, 0),
      attack_id: Keyword.get(opts, :attack_id),
      attack_name: Keyword.get(opts, :attack_name),
      attack_cost: Keyword.get(opts, :attack_cost, []),
      attack_damage: Keyword.get(opts, :attack_damage),
      prompt_ids: Keyword.get(opts, :prompt_ids, []),
      choice_keys: Keyword.get(opts, :choice_keys, []),
      note: Keyword.get(opts, :note)
    }
  end

  defp choice_keys(%Prompt{payload: payload}) do
    case Map.get(payload, "choice_key") do
      choice_key when is_binary(choice_key) -> [choice_key]
      _other -> []
    end
  end

  defp hand_cards(cards), do: Enum.filter(cards, &(&1.zone == :hand))

  defp active_pokemon_card(cards) do
    Enum.find(cards, &(&1.zone == :active))
  end

  defp opponent_active_pokemon_card(cards, player_id) do
    Enum.find(cards, &(&1.zone == :active and &1.owner_player_id != player_id))
  end

  defp in_play_pokemon_cards(cards) do
    cards
    |> Enum.filter(&(&1.zone in [:active, :bench]))
    |> Enum.sort_by(&{zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp bench_pokemon_cards(cards) do
    cards
    |> Enum.filter(&(&1.zone == :bench))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp active_attached_energy_cards(cards, active_card_id) do
    cards
    |> Enum.filter(&(&1.zone == :attached and &1.attached_to_card_instance_id == active_card_id))
    |> Enum.filter(&energy_card?/1)
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp attached_cards_for(cards, card_instance_id) do
    cards
    |> Enum.filter(
      &(&1.zone == :attached and &1.attached_to_card_instance_id == card_instance_id)
    )
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp bench_full?(cards), do: Enum.count(cards, &(&1.zone == :bench)) >= 5

  defp basic_pokemon?(%CardInstance{card_id: card_id}), do: CardCatalog.basic_pokemon?(card_id)

  defp energy_card?(%CardInstance{card_id: card_id}) do
    match?({:ok, %{supertype: :energy}}, CardCatalog.fetch(card_id))
  end

  defp evolution_pokemon?(%CardInstance{card_id: card_id}) do
    match?(
      {:ok, %{supertype: :pokemon, evolves_from: evolves_from}} when not is_nil(evolves_from),
      CardCatalog.fetch(card_id)
    )
  end

  defp can_evolve_target?(%CardInstance{turn_entered_play: turn_entered_play}, turn_number)
       when is_integer(turn_entered_play) do
    turn_entered_play < turn_number
  end

  defp can_evolve_target?(_card, _turn_number), do: false

  defp evolves_from?(%CardInstance{card_id: evolution_card_id}, %CardInstance{
         card_id: target_card_id
       }) do
    with {:ok, evolution_card} <- CardCatalog.fetch(evolution_card_id),
         {:ok, target_card} <- CardCatalog.fetch(target_card_id) do
      evolution_card.evolves_from in [target_card.name, target_card.id]
    else
      _other -> false
    end
  end

  defp retreat_cost(%CardInstance{card_id: card_id}) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{retreat_count: retreat_count}}
      when is_integer(retreat_count) and retreat_count >= 0 ->
        {:ok, retreat_count}

      {:ok, _card} ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp blocked_retreat_status?(%CardInstance{status: status}), do: status in [:asleep, :paralyzed]

  defp blocked_attack_status?(%CardInstance{status: status}), do: status in [:asleep, :paralyzed]

  defp attack_affordance(player, active_card, defender_card, attack_id, attack) do
    cost = AttackCosts.stringify_cost(AttackCosts.attack_cost(attack))
    attack_name = Map.get(attack, :name) || Atom.to_string(attack_id)

    affordance(:declare_attack, "Declare #{attack_name}", :command, player.player_id,
      source_card_instance_ids: [active_card.id],
      target_card_instance_ids: [defender_card.id],
      attack_id: Atom.to_string(attack_id),
      attack_name: attack_name,
      attack_cost: cost,
      attack_damage: attack_damage(attack),
      note: attack_note(cost)
    )
  end

  defp maybe_attack_affordance(
         player,
         active_card,
         defender_card,
         attached_cards,
         attack_id,
         attack
       ) do
    with true <- attack |> AttackCosts.attack_cost() |> AttackCosts.paid?(attached_cards),
         {:ok, executable_attack} <- CardCatalog.fetch_attack(active_card.card_id, attack_id),
         :ok <- AttackEffects.require_declarable_attack(executable_attack, defender_card) do
      [attack_affordance(player, active_card, defender_card, attack_id, executable_attack)]
    else
      _other -> []
    end
  end

  defp unsupported_card_text_affordances(
         %GamePlayer{} = player,
         %Turn{} = current_turn,
         cards,
         all_cards
       ) do
    unsupported_trainer_affordances(player, cards) ++
      unsupported_energy_affordances(player, cards) ++
      unsupported_ability_affordances(player, cards) ++
      unsupported_attack_affordances(player, current_turn, cards, all_cards)
  end

  defp unsupported_trainer_affordances(%GamePlayer{} = player, cards) do
    cards
    |> hand_cards()
    |> Enum.flat_map(fn card ->
      with {:ok, %{supertype: :trainer} = catalog_card} <- CardCatalog.fetch(card.card_id),
           {:pending, reason} <- trainer_pending_reason(card.card_id, catalog_card) do
        [
          affordance(
            :unsupported_trainer,
            "Pending Trainer: #{catalog_card.name}",
            :blocked,
            player.player_id,
            source_card_instance_ids: [card.id],
            note: reason
          )
        ]
      else
        _other -> []
      end
    end)
  end

  defp unsupported_energy_affordances(%GamePlayer{} = player, cards) do
    cards
    |> Enum.filter(&(&1.zone in [:hand, :attached]))
    |> Enum.flat_map(fn card ->
      with {:ok, %{supertype: :energy, energy_type: :special} = catalog_card} <-
             CardCatalog.fetch(card.card_id),
           true <- pending_special_energy_text?(catalog_card) do
        [
          affordance(
            :unsupported_energy,
            "Pending Special Energy: #{catalog_card.name}",
            :blocked,
            player.player_id,
            source_card_instance_ids: [card.id],
            note: special_energy_pending_note(catalog_card)
          )
        ]
      else
        _other -> []
      end
    end)
  end

  defp unsupported_ability_affordances(%GamePlayer{} = player, cards) do
    cards
    |> in_play_pokemon_cards()
    |> Enum.flat_map(fn card ->
      case CardCatalog.fetch(card.card_id) do
        {:ok, %{abilities: abilities, name: card_name, supertype: :pokemon}}
        when is_map(abilities) ->
          abilities
          |> Enum.sort_by(fn {ability_id, _ability} -> Atom.to_string(ability_id) end)
          |> Enum.flat_map(fn {ability_id, ability} ->
            if present_text?(Map.get(ability, :raw_effect)) and is_nil(Map.get(ability, :effect)) do
              ability_name = Map.get(ability, :name) || format_action_id(ability_id)

              [
                affordance(
                  :unsupported_ability,
                  "Pending Ability: #{ability_name}",
                  :blocked,
                  player.player_id,
                  source_card_instance_ids: [card.id],
                  note:
                    "#{card_name}'s #{ability_name} ability has catalog text but no executable engine behavior yet."
                )
              ]
            else
              []
            end
          end)

        _other ->
          []
      end
    end)
  end

  defp unsupported_attack_affordances(
         %GamePlayer{} = player,
         %Turn{} = current_turn,
         cards,
         all_cards
       ) do
    with %CardInstance{} = active_card <- active_pokemon_card(cards),
         false <- blocked_attack_status?(active_card),
         false <- AttackLocks.blocked_this_turn?(active_card, current_turn),
         true <-
           AttackRequirements.attack_restrictions_met?(active_card, in_play_pokemon_cards(cards)),
         %CardInstance{} <- opponent_active_pokemon_card(all_cards, player.player_id),
         {:ok, %{attacks: attacks}} <- CardCatalog.fetch(active_card.card_id) do
      attached_cards = attached_cards_for(cards, active_card.id)

      attacks
      |> Enum.sort_by(fn {attack_id, _attack} -> Atom.to_string(attack_id) end)
      |> Enum.flat_map(fn {attack_id, attack} ->
        attack_cost = AttackCosts.attack_cost(attack)

        if AttackCosts.paid?(attack_cost, attached_cards) do
          case CardCatalog.fetch_attack(active_card.card_id, attack_id) do
            {:ok, _attack} ->
              []

            {:error, reason} ->
              [unsupported_attack_affordance(player, active_card, attack_id, attack, reason)]
          end
        else
          []
        end
      end)
    else
      _other -> []
    end
  end

  defp unsupported_attack_affordance(player, active_card, attack_id, attack, reason) do
    cost = AttackCosts.stringify_cost(AttackCosts.attack_cost(attack))
    attack_name = Map.get(attack, :name) || format_action_id(attack_id)

    affordance(:unsupported_attack, "Pending Attack: #{attack_name}", :blocked, player.player_id,
      source_card_instance_ids: [active_card.id],
      attack_id: Atom.to_string(attack_id),
      attack_name: attack_name,
      attack_cost: cost,
      attack_damage: attack_damage(attack),
      note: unsupported_attack_note(reason)
    )
  end

  defp trainer_pending_reason(card_id, %{raw_effect: raw_effect}) do
    with true <- present_text?(raw_effect),
         {:ok, definition} <- EngineCardRegistry.fetch(card_id),
         false <- Map.get(definition, :play_window) == :action_window do
      {:pending,
       "This Trainer has authored behavior, but that timing window is not exposed in the current action surface."}
    else
      {:error, _reason} ->
        {:pending,
         "Trainer text has no executable engine behavior yet, so no Play command appears."}

      _other ->
        false
    end
  end

  defp special_energy_pending_note(%{name: "Team Rocket's Energy"}) do
    "Team Rocket's Energy has narrow attack-cost provider support, but attachment restrictions and remaining printed text are still pending."
  end

  defp special_energy_pending_note(%{provides: provides})
       when is_list(provides) and provides != [] do
    "This Special Energy can provide Energy for generic attack costs, but remaining printed effects are still pending."
  end

  defp special_energy_pending_note(_card) do
    "This Special Energy can attach generically, but its printed Energy rule or effects are still pending."
  end

  defp pending_special_energy_text?(card) do
    present_text?(Map.get(card, :raw_effect)) and not supported_special_energy?(card)
  end

  defp supported_special_energy?(%{
         effect: %{type: :draw_cards_on_attach_from_hand, count: count},
         provides: provides
       })
       when is_integer(count) and count > 0 and is_list(provides) do
    :colorless in provides
  end

  defp supported_special_energy?(_card), do: false

  defp unsupported_attack_note({:unsupported_attack_effect, _card_id, _attack_id, effect_type}) do
    "This paid attack is visible on the Active Pokémon, but effect #{format_action_id(effect_type)} is not executable yet."
  end

  defp unsupported_attack_note(_reason) do
    "This paid attack is visible on the Active Pokémon, but its card text has no executable engine behavior yet."
  end

  defp attack_damage(%{damage: damage}) when is_integer(damage), do: Integer.to_string(damage)
  defp attack_damage(%{damage: damage}) when is_binary(damage), do: damage
  defp attack_damage(_attack), do: nil

  defp attack_note([]) do
    "Declaration validates this free attack. Damage and effects resolve in follow-up attack commands."
  end

  defp attack_note(cost) do
    "Declaration validates attached Energy cost #{Enum.join(cost, ", ")}. Damage and effects resolve in follow-up attack commands."
  end

  defp present_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp present_text?(_text), do: false

  defp format_action_id(value) when is_atom(value),
    do: value |> Atom.to_string() |> format_action_id()

  defp format_action_id(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_action_id(value), do: value |> to_string() |> format_action_id()

  defp retreat_note(0),
    do: "Switch the Active Pokémon with a Benched Pokémon without discarding Energy."

  defp retreat_note(1),
    do: "Discard 1 Energy attached to the Active Pokémon, then switch it with a Benched Pokémon."

  defp retreat_note(retreat_cost),
    do:
      "Discard #{retreat_cost} Energy attached to the Active Pokémon, then switch it with a Benched Pokémon."

  defp engine_playable_card?(%CardInstance{card_id: card_id} = card, cards) do
    case EngineCardRegistry.fetch(card_id) do
      {:ok, %{play_window: :action_window} = definition} ->
        CardPlay.required_choices_available?(cards, card, definition)

      {:ok, _definition} ->
        false

      {:error, _reason} ->
        false
    end
  end

  defp card_ids(cards), do: Enum.map(cards, & &1.id)

  defp zone_sort(:active), do: 0
  defp zone_sort(:bench), do: 1
end
