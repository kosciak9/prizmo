defmodule Prizmo.TcgEngine.GameView do
  @moduledoc false

  alias Prizmo.TcgEngine.AttackEffects
  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GameEvent
  alias Prizmo.TcgEngine.GameStore
  alias Prizmo.TcgEngine.GameView.ActionAffordances
  alias Prizmo.TcgEngine.PlayerStore
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Setup
  alias Prizmo.TcgEngine.Turn
  alias Prizmo.TcgEngine.TurnStore

  require Ash.Query

  @doc "Returns a viewer-scoped read model for the persisted game state."
  def for_player(game_id, viewer_player_id)
      when is_binary(game_id) and is_binary(viewer_player_id) do
    with {:ok, game} <- GameStore.get_game(game_id),
         {:ok, players} <- PlayerStore.list_players(game.id),
         :ok <- require_viewer(players, viewer_player_id),
         {:ok, cards} <- CardStore.list_cards(game.id),
         {:ok, events} <- list_events(game),
         {:ok, setup} <- maybe_setup(game.id),
         {:ok, current_turn} <- maybe_current_turn(game.id),
         {:ok, prompts} <- list_viewer_prompts(game.id, viewer_player_id) do
      attached_cards_by_target = attached_cards_by_target(cards)

      {:ok,
       %{
         game_id: game.id,
         viewer_player_id: viewer_player_id,
         status: stringify(game.status),
         active_player_id: game.active_player_id,
         first_player_id: game.first_player_id,
         winner_player_id: game.winner_player_id,
         cursor_index: game.cursor_index,
         latest_event_index: game.latest_event_index,
         setup: setup_view(setup),
         current_turn: turn_view(current_turn, cards),
         action_affordances:
           ActionAffordances.for_viewer(
             game,
             current_turn,
             players,
             cards,
             prompts,
             viewer_player_id
           ),
         stadium: stadium_view(cards, attached_cards_by_target),
         players: player_views(players, cards, viewer_player_id, attached_cards_by_target),
         events: Enum.map(events, &event_view/1),
         prompts: Enum.map(prompts, &prompt_view(&1, cards, attached_cards_by_target))
       }}
    end
  end

  def for_player(_game_id, _viewer_player_id), do: {:error, :invalid_game_view_arguments}

  defp require_viewer(players, viewer_player_id) do
    if Enum.any?(players, &(&1.player_id == viewer_player_id)) do
      :ok
    else
      {:error, :viewer_player_not_found}
    end
  end

  defp maybe_setup(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one()
  end

  defp maybe_current_turn(game_id), do: TurnStore.latest_turn(game_id)

  defp list_events(%Game{} = game) do
    GameEvent
    |> Ash.Query.filter(game_id == ^game.id and index <= ^game.cursor_index)
    |> Ash.Query.sort(index: :asc)
    |> Ash.read()
  end

  defp list_viewer_prompts(game_id, viewer_player_id) do
    Prompt
    |> Ash.Query.filter(
      game_id == ^game_id and player_id == ^viewer_player_id and status == :awaiting_choice
    )
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.read()
  end

  defp setup_view(nil), do: nil

  defp setup_view(%Setup{} = setup) do
    %{
      id: setup.id,
      status: stringify(setup.status)
    }
  end

  defp turn_view(nil, _cards), do: nil

  defp turn_view(%Turn{} = turn, cards) do
    pending_attack_effect_type = pending_attack_effect_type(turn, cards)

    %{
      id: turn.id,
      turn_number: turn.turn_number,
      active_player_id: turn.active_player_id,
      status: stringify(turn.status),
      visible: turn.visible?,
      pending_attack_id: stringify(turn.pending_attack_id),
      pending_attack_effect_type: stringify(pending_attack_effect_type),
      pending_attack_requires_switch_target:
        pending_attack_effect_type == :switch_self_with_bench,
      pending_attack_requires_discarded_energy:
        pending_attack_effect_type in [
          :damage_per_discarded_own_basic_energy,
          :discard_energy_from_own_bench_for_bonus_damage
        ],
      pending_attack_requires_returned_energy:
        pending_attack_effect_type == :return_attached_energy_to_hand,
      pending_attacker_card_instance_id: turn.pending_attacker_card_instance_id,
      pending_defender_card_instance_id: turn.pending_defender_card_instance_id
    }
  end

  defp pending_attack_effect_type(
         %Turn{pending_attack_id: attack_id, pending_attacker_card_instance_id: attacker_id},
         cards
       )
       when not is_nil(attack_id) and not is_nil(attacker_id) do
    with %CardInstance{} = attacker_card <- Enum.find(cards, &(&1.id == attacker_id)),
         {:ok, %{effect: effect}} when is_map(effect) <-
           CardCatalog.fetch_attack(attacker_card.card_id, attack_id) do
      AttackEffects.type(effect)
    else
      _other -> nil
    end
  end

  defp pending_attack_effect_type(%Turn{}, _cards), do: nil

  defp stadium_view(cards, attached_cards_by_target) do
    cards
    |> cards_in_zone(:stadium)
    |> List.first()
    |> card_view(attached_cards_by_target)
  end

  defp player_views(players, cards, viewer_player_id, attached_cards_by_target) do
    cards_by_player = Enum.group_by(cards, & &1.owner_player_id)

    Enum.map(players, fn player ->
      player_cards = Map.get(cards_by_player, player.player_id, [])
      viewer? = player.player_id == viewer_player_id

      %{
        player_id: player.player_id,
        deck_key: player.deck_key,
        energy_attached_this_turn: player.energy_attached_this_turn?,
        supporter_played_this_turn: player.supporter_played_this_turn?,
        retreated_this_turn: player.retreated_this_turn?,
        ace_spec_played_this_game: player.ace_spec_played_this_game?,
        deck_count: zone_count(player_cards, :deck),
        hand_count: zone_count(player_cards, :hand),
        prize_count: zone_count(player_cards, :prize),
        discard_count: zone_count(player_cards, :discard),
        active:
          player_cards
          |> cards_in_zone(:active)
          |> List.first()
          |> card_view(attached_cards_by_target),
        bench:
          player_cards
          |> cards_in_zone(:bench)
          |> Enum.map(&card_view(&1, attached_cards_by_target)),
        hand: private_hand_view(player_cards, viewer?, attached_cards_by_target),
        discard:
          player_cards
          |> cards_in_zone(:discard)
          |> Enum.map(&card_view(&1, attached_cards_by_target))
      }
    end)
  end

  defp private_hand_view(player_cards, true, attached_cards_by_target) do
    player_cards
    |> cards_in_zone(:hand)
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp private_hand_view(_player_cards, false, _attached_cards_by_target), do: []

  defp attached_cards_by_target(cards) do
    cards
    |> Enum.reject(&is_nil(&1.attached_to_card_instance_id))
    |> Enum.group_by(& &1.attached_to_card_instance_id)
    |> Map.new(fn {target_id, attached_cards} ->
      {target_id, sort_attached_cards(attached_cards)}
    end)
  end

  defp sort_attached_cards(cards) do
    Enum.sort_by(cards, &{&1.position, &1.instance_id})
  end

  defp cards_in_zone(cards, zone) do
    cards
    |> Enum.filter(&(&1.zone == zone))
    |> Enum.sort_by(&{&1.position, &1.instance_id})
  end

  defp zone_count(cards, zone), do: Enum.count(cards, &(&1.zone == zone))

  defp card_view(nil, _attached_cards_by_target), do: nil

  defp card_view(%CardInstance{} = card, attached_cards_by_target) do
    card
    |> card_summary()
    |> Map.put(
      :attached_cards,
      attached_card_views(card.id, attached_cards_by_target)
    )
  end

  defp attached_card_views(card_id, attached_cards_by_target) do
    attached_cards_by_target
    |> Map.get(card_id, [])
    |> Enum.map(&card_summary/1)
  end

  defp card_summary(%CardInstance{} = card) do
    catalog = catalog_card(card.card_id)

    %{
      id: card.id,
      instance_id: card.instance_id,
      card_id: card.card_id,
      name: Map.get(catalog, :name, card.card_id),
      image: Map.get(catalog, :image),
      category: stringify(Map.get(catalog, :category)),
      stage: stringify(Map.get(catalog, :stage)),
      owner_player_id: card.owner_player_id,
      zone: stringify(card.zone),
      position: card.position,
      damage: card.damage,
      status: stringify(card.status),
      attached_to_card_instance_id: card.attached_to_card_instance_id,
      evolves_from_card_instance_id: card.evolves_from_card_instance_id,
      turn_entered_play: card.turn_entered_play
    }
  end

  defp event_view(%GameEvent{} = event) do
    %{
      id: event.id,
      index: event.index,
      type: event.type,
      player_id: event.player_id,
      turn_id: event.turn_id
    }
  end

  defp prompt_view(%Prompt{} = prompt, cards, attached_cards_by_target) do
    %{
      id: prompt.id,
      prompt_type: prompt.prompt_type,
      status: stringify(prompt.status),
      player_id: prompt.player_id,
      payload: prompt_payload(prompt, cards, attached_cards_by_target)
    }
  end

  defp prompt_payload(%Prompt{payload: payload} = prompt, cards, attached_cards_by_target) do
    choice_cards = legal_choice_cards(prompt, cards, attached_cards_by_target)

    if Enum.empty?(choice_cards) do
      payload
    else
      Map.put(payload, "legal_choice_cards", choice_cards)
    end
  end

  defp legal_choice_cards(
         %Prompt{prompt_type: "choose_knockout_prizes"},
         _cards,
         _attached_cards_by_target
       ), do: []

  defp legal_choice_cards(
         %Prompt{payload: payload, player_id: player_id},
         cards,
         attached_cards_by_target
       ) do
    cards_by_id = Map.new(cards, &{&1.id, &1})

    payload
    |> Map.get("legal_choices", [])
    |> case do
      ids when is_list(ids) -> ids
      _other -> []
    end
    |> Enum.map(&Map.get(cards_by_id, &1))
    |> Enum.filter(fn
      %CardInstance{owner_player_id: ^player_id} -> true
      _other -> false
    end)
    |> Enum.map(&card_view(&1, attached_cards_by_target))
  end

  defp catalog_card(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> card
      {:error, _reason} -> %{}
    end
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value
end
