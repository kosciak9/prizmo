defmodule Prizmo.TcgEngine.CardStore do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardInstance

  require Ash.Query

  def get_card(game_id, card_instance_id) do
    case CardInstance
         |> Ash.Query.filter(game_id == ^game_id and id == ^card_instance_id)
         |> Ash.read_one() do
      {:ok, %CardInstance{} = card} -> {:ok, card}
      {:ok, nil} -> {:error, :card_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_cards(_game_id, []), do: {:ok, []}

  def get_cards(game_id, card_instance_ids) do
    card_instance_ids
    |> Enum.map(&get_card(game_id, &1))
    |> collect_results()
  end

  def list_cards(game_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(owner_player_id: :asc, zone: :asc, position: :asc, instance_id: :asc)
    |> Ash.read()
  end

  def cards_in_zone(game_id, zone) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and zone == ^zone)
    |> Ash.Query.sort(owner_player_id: :asc, position: :asc, instance_id: :asc)
    |> Ash.read()
  end

  def cards_in_zone(game_id, player_id, zone) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and owner_player_id == ^player_id and zone == ^zone)
    |> Ash.Query.sort(position: :asc, instance_id: :asc)
    |> Ash.read()
  end

  def attached_cards(game_id, target_card_instance_id) do
    CardInstance
    |> Ash.Query.filter(
      game_id == ^game_id and attached_to_card_instance_id == ^target_card_instance_id
    )
    |> Ash.Query.sort(position: :asc, instance_id: :asc)
    |> Ash.read()
  end

  def deck_cards_for_player(game_player_id, limit) do
    CardInstance
    |> Ash.Query.filter(game_player_id == ^game_player_id and zone == :deck)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  def non_deck_cards(game_id) do
    CardInstance
    |> Ash.Query.filter(game_id == ^game_id and zone != :deck)
    |> Ash.read()
  end

  def next_hand_position(game_id, player_id) do
    case cards_in_zone(game_id, player_id, :hand) do
      {:ok, hand} -> length(hand) + 1
      {:error, _reason} -> 1
    end
  end

  def next_hand_position_result(game_id, player_id) do
    with {:ok, hand} <- cards_in_zone(game_id, player_id, :hand) do
      {:ok, length(hand) + 1}
    end
  end

  def next_attachment_position(game_id, target_card_instance_id) do
    with {:ok, attachments} <- attached_cards(game_id, target_card_instance_id) do
      {:ok, length(attachments) + 1}
    end
  end

  def reparent_attached_cards(game_id, from_target_card_instance_id, to_target_card_instance_id) do
    with {:ok, attachments} <- attached_cards(game_id, from_target_card_instance_id) do
      attachments
      |> Enum.with_index(2)
      |> Enum.map(fn {attachment, position} ->
        update(attachment, :reparent_attachment, %{
          attached_to_card_instance_id: to_target_card_instance_id,
          position: position
        })
      end)
      |> collect_results()
    end
  end

  def next_discard_position(game_id, player_id) do
    with {:ok, discard} <- cards_in_zone(game_id, player_id, :discard) do
      {:ok, length(discard) + 1}
    end
  end

  def next_bench_position(game_id, player_id) do
    with {:ok, bench} <- cards_in_zone(game_id, player_id, :bench) do
      if length(bench) < 5 do
        {:ok, length(bench) + 1}
      else
        {:error, :bench_full}
      end
    end
  end

  def discard_existing_stadiums(game_id) do
    with {:ok, stadiums} <- cards_in_zone(game_id, :stadium) do
      stadiums
      |> Enum.map(fn stadium ->
        with {:ok, position} <- next_discard_position(game_id, stadium.owner_player_id) do
          update(stadium, :discard, %{position: position})
        end
      end)
      |> collect_results()
    end
  end

  def discard_cards_from_hand(game_id, player_id, cards) do
    cards
    |> Enum.map(fn card ->
      with {:ok, position} <- next_discard_position(game_id, player_id) do
        update(card, :discard, %{position: position})
      end
    end)
    |> collect_results()
  end

  def move_deck_card_to_hand(game_id, player_id, %CardInstance{} = card) do
    with {:ok, position} <- next_hand_position_result(game_id, player_id) do
      update(card, :draw_to_hand, %{position: position})
    end
  end

  def move_discard_card_to_hand(game_id, player_id, %CardInstance{} = card) do
    with {:ok, position} <- next_hand_position_result(game_id, player_id) do
      update(card, :recover_to_hand, %{position: position})
    end
  end

  def move_card_to_hand(%CardInstance{} = card, :deck, position) do
    update(card, :draw_to_hand, %{position: position})
  end

  def move_card_to_hand(%CardInstance{} = card, :discard, position) do
    update(card, :recover_to_hand, %{position: position})
  end

  def move_deck_cards_to_bench(game_id, player_id, cards, turn_number) do
    cards
    |> Enum.map(fn card ->
      with {:ok, position} <- next_bench_position(game_id, player_id) do
        update(card, :put_basic_from_deck_to_bench, %{
          position: position,
          turn_entered_play: turn_number
        })
      end
    end)
    |> collect_results()
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
end
