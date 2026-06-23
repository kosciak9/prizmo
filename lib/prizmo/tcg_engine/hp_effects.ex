defmodule Prizmo.TcgEngine.HpEffects do
  @moduledoc false

  import Prizmo.TcgEngine.CardMetadataRequirements, only: [pokemon_hp: 1]

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance
  alias Prizmo.TcgEngine.CardStore
  alias Prizmo.TcgEngine.StadiumEffects

  @gravity_mountain_effect :stage_2_pokemon_hp_modifier
  @hero_cape_effect :attached_pokemon_hp_modifier

  def effective_hp(game_id, %CardInstance{} = card) when is_binary(game_id) do
    with {:ok, base_hp} <- pokemon_hp(card.card_id) do
      modifier =
        stage_2_stadium_hp_modifier(game_id, card) +
          attached_tool_hp_modifier(game_id, card)

      {:ok, max(base_hp + modifier, 0)}
    end
  end

  def remaining_hp(game_id, %CardInstance{damage: damage} = card) when is_binary(game_id) do
    with {:ok, effective_hp} <- effective_hp(game_id, card) do
      {:ok, max(effective_hp - (damage || 0), 0)}
    end
  end

  def damage_knocks_out?(game_id, %CardInstance{} = card, resulting_damage)
      when is_binary(game_id) and is_integer(resulting_damage) do
    with {:ok, effective_hp} <- effective_hp(game_id, card) do
      {:ok, resulting_damage >= effective_hp}
    end
  end

  defp stage_2_stadium_hp_modifier(game_id, %CardInstance{} = card) when is_binary(game_id) do
    with true <- card.zone in [:active, :bench],
         {:ok, %{supertype: :pokemon, stage: :stage_2}} <- CardCatalog.fetch(card.card_id),
         true <- gravity_mountain_active?(game_id) do
      -30
    else
      _other -> 0
    end
  end

  defp attached_tool_hp_modifier(game_id, %CardInstance{} = card) when is_binary(game_id) do
    with true <- card.zone in [:active, :bench],
         false <- StadiumEffects.tools_have_no_effect?(game_id),
         {:ok, attachments} <- CardStore.attached_cards(game_id, card.id) do
      Enum.reduce(attachments, 0, fn attached_card, total ->
        total + tool_hp_modifier(attached_card)
      end)
    else
      _other -> 0
    end
  end

  defp tool_hp_modifier(%CardInstance{card_id: card_id}) when is_binary(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok,
       %{
         supertype: :trainer,
         trainer_type: :tool,
         effect: %{type: @hero_cape_effect, amount: amount}
       }}
      when is_integer(amount) ->
        amount

      _other ->
        0
    end
  end

  defp gravity_mountain_active?(game_id) when is_binary(game_id) do
    case CardStore.cards_in_zone(game_id, :stadium) do
      {:ok, stadiums} ->
        Enum.any?(stadiums, fn
          %CardInstance{card_id: card_id} when is_binary(card_id) ->
            case CardCatalog.fetch(card_id) do
              {:ok,
               %{
                 supertype: :trainer,
                 trainer_type: :stadium,
                 effect: %{type: @gravity_mountain_effect}
               }} ->
                true

              _other ->
                false
            end

          _other ->
            false
        end)

      _other ->
        false
    end
  end
end
