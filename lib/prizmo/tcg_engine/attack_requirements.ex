defmodule Prizmo.TcgEngine.AttackRequirements do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore

  @spec require_card_attack_restrictions(String.t(), CardInstance.t()) :: :ok | {:error, term()}
  def require_card_attack_restrictions(game_id, %CardInstance{owner_player_id: player_id} = card)
      when is_binary(game_id) do
    with {:ok, active_cards} <- CardStore.cards_in_zone(game_id, player_id, :active),
         {:ok, bench_cards} <- CardStore.cards_in_zone(game_id, player_id, :bench) do
      require_card_attack_restrictions(card, active_cards ++ bench_cards)
    end
  end

  @spec require_card_attack_restrictions(CardInstance.t(), [CardInstance.t()]) ::
          :ok | {:error, term()}
  def require_card_attack_restrictions(%CardInstance{} = card, own_in_play_cards)
      when is_list(own_in_play_cards) do
    with {:ok, metadata} <- CardCatalog.fetch(card.card_id) do
      metadata.abilities
      |> Map.values()
      |> Enum.map(&require_ability_attack_restriction(&1, own_in_play_cards))
      |> collect_ok_results()
    end
  end

  @spec attack_restrictions_met?(CardInstance.t(), [CardInstance.t()]) :: boolean()
  def attack_restrictions_met?(%CardInstance{} = card, own_in_play_cards)
      when is_list(own_in_play_cards) do
    require_card_attack_restrictions(card, own_in_play_cards) == :ok
  end

  defp require_ability_attack_restriction(
         %{
           effect: %{
             type: :cannot_attack_unless_own_team_rocket_pokemon_in_play,
             count: required_count
           }
         },
         own_in_play_cards
       )
       when is_integer(required_count) and required_count >= 0 do
    if own_team_rocket_pokemon_count(own_in_play_cards) >= required_count do
      :ok
    else
      {:error, {:not_enough_own_team_rocket_pokemon_in_play, required_count}}
    end
  end

  defp require_ability_attack_restriction(_ability, _own_in_play_cards), do: :ok

  defp own_team_rocket_pokemon_count(cards) do
    cards
    |> Enum.map(&team_rocket_pokemon?/1)
    |> Enum.count(&(&1 == true))
  end

  defp team_rocket_pokemon?(%CardInstance{card_id: card_id}) do
    match?(
      {:ok, %{supertype: :pokemon, name: "Team Rocket's " <> _name}},
      CardCatalog.fetch(card_id)
    )
  end

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end
end
