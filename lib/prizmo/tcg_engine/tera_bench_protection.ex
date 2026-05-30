defmodule Prizmo.TcgEngine.TeraBenchProtection do
  @moduledoc false

  alias Prizmo.TcgEngine.CardCatalog
  alias Prizmo.TcgEngine.CardInstance

  @spec prevents_attack_damage?(CardInstance.t()) :: boolean()
  def prevents_attack_damage?(%CardInstance{zone: :bench, card_id: card_id}) do
    CardCatalog.tera_pokemon?(card_id)
  end

  def prevents_attack_damage?(%CardInstance{}), do: false

  @spec prevented_attack_damage_result(CardInstance.t(), non_neg_integer()) :: map()
  def prevented_attack_damage_result(%CardInstance{} = card, damage) do
    %{
      damage: 0,
      prevented_damage: damage,
      resulting_damage: card.damage,
      knocked_out?: false,
      damage_prevented?: true,
      damage_prevention: "tera_bench_protection",
      tera_bench_damage_prevented?: true,
      protected_card_instance_id: card.id,
      protected_card_id: card.card_id
    }
  end
end
