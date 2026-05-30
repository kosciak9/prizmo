defmodule Prizmo.TcgEngine.CardMetadataRequirements do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog

  def require_basic_pokemon(card_id) do
    if CardCatalog.basic_pokemon?(card_id) do
      :ok
    else
      {:error, :not_basic_pokemon}
    end
  end

  def require_energy(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :energy}} -> :ok
      {:ok, _card} -> {:error, :not_energy}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_basic_energy(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :energy, energy_type: :basic}} -> :ok
      {:ok, %{supertype: :energy}} -> {:error, :not_basic_energy}
      {:ok, _card} -> {:error, :not_energy}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_pokemon_card(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon}} -> :ok
      {:ok, metadata} -> {:error, {:not_pokemon, metadata.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_non_rule_box_pokemon_card(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, rule_box?: true} = metadata} ->
        {:error, {:pokemon_has_rule_box, metadata.id}}

      {:ok, %{supertype: :pokemon}} ->
        :ok

      {:ok, metadata} ->
        {:error, {:not_pokemon, metadata.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def require_night_stretcher_target(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon}} -> :ok
      {:ok, %{supertype: :energy, energy_type: :basic}} -> :ok
      {:ok, metadata} -> {:error, {:invalid_night_stretcher_target, metadata.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_poffin_targets(targets) do
    targets
    |> Enum.map(fn target ->
      with :ok <- require_basic_pokemon(target.card_id),
           {:ok, hp} <- pokemon_hp(target.card_id),
           true <- hp <= 70 || {:error, {:poffin_target_hp_too_high, target.card_id, hp}} do
        :ok
      end
    end)
    |> collect_ok_results()
  end

  def require_trainer_type(card_id, allowed_types) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :trainer, trainer_type: trainer_type} = metadata} ->
        if trainer_type in allowed_types do
          {:ok, metadata}
        else
          {:error, {:invalid_trainer_type, trainer_type, allowed_types}}
        end

      {:ok, _card} ->
        {:error, :not_trainer}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def require_evolves_from(evolution_card_id, target_card_id) do
    with {:ok, evolution_card} <- CardCatalog.fetch(evolution_card_id),
         {:ok, target_card} <- CardCatalog.fetch(target_card_id) do
      cond do
        evolution_card.supertype != :pokemon ->
          {:error, :evolution_card_is_not_pokemon}

        is_nil(evolution_card.evolves_from) ->
          {:error, :card_does_not_evolve}

        evolution_card.evolves_from in [target_card.name, target_card.id] ->
          :ok

        true ->
          {:error, {:invalid_evolution_target, evolution_card.evolves_from, target_card.name}}
      end
    end
  end

  def retreat_cost(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, retreat_count: retreat_count}}
      when is_integer(retreat_count) ->
        {:ok, retreat_count}

      {:ok, %{supertype: :pokemon}} ->
        {:ok, 0}

      {:ok, _card} ->
        {:error, :active_card_is_not_pokemon}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def pokemon_hp(card_id) do
    case CardCatalog.fetch(card_id) do
      {:ok, %{supertype: :pokemon, hp: hp}} when is_integer(hp) -> {:ok, hp}
      {:ok, %{supertype: :pokemon, hp: hp}} when is_binary(hp) -> parse_hp(hp)
      {:ok, %{supertype: :pokemon}} -> {:error, :pokemon_hp_unknown}
      {:ok, _card} -> {:error, :not_pokemon}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_hp(hp) when is_binary(hp) do
    case Integer.parse(hp) do
      {value, ""} -> {:ok, value}
      _other -> {:error, :pokemon_hp_unknown}
    end
  end

  defp collect_ok_results(results) do
    Enum.reduce_while(results, :ok, fn
      :ok, :ok -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end
end
