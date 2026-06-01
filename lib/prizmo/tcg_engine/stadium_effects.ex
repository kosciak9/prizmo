defmodule Prizmo.TcgEngine.StadiumEffects do
  @moduledoc false

  import Prizmo.TcgEngine.Operation, only: [update: 3]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  @special_condition_immunity_effect :special_condition_immunity_for_pokemon_with_energy
  @special_conditions [:asleep, :burned, :confused, :paralyzed, :poisoned]
  @festival_grounds_effect_id "festival_grounds"

  def supported_stadium?(%{
        supertype: :trainer,
        trainer_type: :stadium,
        effect: %{type: @special_condition_immunity_effect}
      }),
      do: true

  def supported_stadium?(_card), do: false

  def supported_stadium_card?(card_id) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, card} -> supported_stadium?(card)
      {:error, _reason} -> false
    end
  end

  def recover_special_conditions(game_id) when is_binary(game_id) do
    with {:ok, stadium} <- active_special_condition_immunity_stadium(game_id) do
      case stadium do
        %CardInstance{} = stadium -> recover_in_play_special_conditions(game_id, stadium)
        nil -> {:ok, []}
      end
    end
  end

  def recover_special_condition(game_id, %CardInstance{} = card) when is_binary(game_id) do
    with {:ok, stadium} <- active_special_condition_immunity_stadium(game_id) do
      case stadium do
        %CardInstance{} = stadium -> recover_card_special_condition(game_id, stadium, card)
        nil -> {:ok, nil}
      end
    end
  end

  def status_condition_prevention_payload(game_id, %CardInstance{} = card, status)
      when is_binary(game_id) do
    with true <- special_condition?(status),
         true <- in_play?(card),
         {:ok, %CardInstance{} = stadium} <- active_special_condition_immunity_stadium(game_id),
         true <- energy_attached?(game_id, card) do
      {:prevented, prevention_payload(stadium, card, status)}
    else
      _other -> :not_prevented
    end
  end

  defp active_special_condition_immunity_stadium(game_id) do
    with {:ok, stadiums} <- CardStore.cards_in_zone(game_id, :stadium) do
      stadium = Enum.find(stadiums, &special_condition_immunity_stadium?/1)
      {:ok, stadium}
    end
  end

  defp special_condition_immunity_stadium?(%CardInstance{card_id: card_id}) do
    card_id
    |> CardCatalog.fetch()
    |> case do
      {:ok, card} -> supported_stadium?(card)
      {:error, _reason} -> false
    end
  end

  defp recover_in_play_special_conditions(game_id, %CardInstance{} = stadium) do
    with {:ok, cards} <- in_play_cards(game_id) do
      cards
      |> Enum.map(&recover_card_special_condition(game_id, stadium, &1))
      |> collect_recoveries()
    end
  end

  defp in_play_cards(game_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, :bench) do
      {:ok, active_cards ++ bench_cards}
    end
  end

  defp recover_card_special_condition(game_id, %CardInstance{} = stadium, %CardInstance{} = card) do
    if recoverable_special_condition?(game_id, card) do
      with {:ok, _card} <- update(card, :set_status, %{status: nil}) do
        {:ok, recovery_payload(stadium, card)}
      end
    else
      {:ok, nil}
    end
  end

  defp recoverable_special_condition?(game_id, %CardInstance{status: status} = card) do
    special_condition?(status) and in_play?(card) and energy_attached?(game_id, card)
  end

  defp energy_attached?(game_id, %CardInstance{} = card) do
    case CardStore.attached_cards(game_id, card.id) do
      {:ok, attached_cards} -> Enum.any?(attached_cards, &energy_card?/1)
      {:error, _reason} -> false
    end
  end

  defp energy_card?(%CardInstance{card_id: card_id}) do
    card_id
    |> CardCatalog.fetch()
    |> case do
      {:ok, %{supertype: :energy}} -> true
      {:ok, _card} -> false
      {:error, _reason} -> false
    end
  end

  defp recovery_payload(%CardInstance{} = stadium, %CardInstance{} = card) do
    %{
      card_instance_id: card.id,
      card_id: card.card_id,
      owner_player_id: card.owner_player_id,
      recovered_status: Atom.to_string(card.status),
      stadium_card_id: stadium.card_id,
      stadium_card_instance_id: stadium.id,
      stadium_effect_id: @festival_grounds_effect_id
    }
  end

  defp prevention_payload(%CardInstance{} = stadium, %CardInstance{} = card, status) do
    %{
      protected_card_instance_id: card.id,
      prevented_status: Atom.to_string(status),
      status_prevention_source_card_id: stadium.card_id,
      status_prevention_source_card_instance_id: stadium.id,
      status_prevention_source_effect_id: @festival_grounds_effect_id,
      status_prevention_source_player_id: stadium.owner_player_id
    }
  end

  defp special_condition?(status), do: status in @special_conditions
  defp in_play?(%CardInstance{zone: zone}), do: zone in [:active, :bench]

  defp collect_recoveries(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, nil}, {:ok, acc} -> {:cont, {:ok, acc}}
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end
end
