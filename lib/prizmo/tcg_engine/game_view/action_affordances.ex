defmodule Prizmo.TcgEngine.GameView.ActionAffordances do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.Cards.Registry, as: EngineCardRegistry
  alias Prizmo.TcgEngine.Game
  alias Prizmo.TcgEngine.GamePlayer
  alias Prizmo.TcgEngine.Prompt
  alias Prizmo.TcgEngine.Turn

  @doc "Returns action affordances visible to the current game viewer."
  def for_viewer(%Game{} = game, current_turn, players, cards, prompts, viewer_player_id)
      when is_list(players) and is_list(cards) and is_list(prompts) and
             is_binary(viewer_player_id) do
    case prompt_affordances(prompts) do
      [] -> action_window_affordances(game, current_turn, players, cards, viewer_player_id)
      prompt_actions -> prompt_actions
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

  defp action_window_affordances(game, current_turn, players, cards, viewer_player_id) do
    if action_window_for_viewer?(game, current_turn, viewer_player_id) do
      player = Enum.find(players, &(&1.player_id == viewer_player_id))
      viewer_cards = Enum.filter(cards, &(&1.owner_player_id == viewer_player_id))

      player
      |> available_action_window_affordances(viewer_cards)
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

  defp available_action_window_affordances(nil, _cards), do: []

  defp available_action_window_affordances(%GamePlayer{} = player, cards) do
    [
      play_card_affordance(player, cards),
      play_basic_to_bench_affordance(player, cards),
      attach_energy_affordance(player, cards),
      end_turn_affordance(player)
    ]
  end

  defp play_card_affordance(%GamePlayer{} = player, cards) do
    source_ids =
      cards
      |> hand_cards()
      |> Enum.filter(&engine_playable_card?/1)
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

  defp end_turn_affordance(%GamePlayer{} = player) do
    affordance(:end_turn, "End turn", :command, player.player_id,
      note: "Pass the action to the next player after resolving optional actions."
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

  defp in_play_pokemon_cards(cards) do
    cards
    |> Enum.filter(&(&1.zone in [:active, :bench]))
    |> Enum.sort_by(&{zone_sort(&1.zone), &1.position, &1.instance_id})
  end

  defp bench_full?(cards), do: Enum.count(cards, &(&1.zone == :bench)) >= 5

  defp basic_pokemon?(%CardInstance{card_id: card_id}), do: CardCatalog.basic_pokemon?(card_id)

  defp energy_card?(%CardInstance{card_id: card_id}) do
    match?({:ok, %{supertype: :energy}}, CardCatalog.fetch(card_id))
  end

  defp engine_playable_card?(%CardInstance{card_id: card_id}) do
    case EngineCardRegistry.fetch(card_id) do
      {:ok, %{play_window: :action_window}} -> true
      {:ok, _definition} -> false
      {:error, _reason} -> false
    end
  end

  defp card_ids(cards), do: Enum.map(cards, & &1.id)

  defp zone_sort(:active), do: 0
  defp zone_sort(:bench), do: 1
end
