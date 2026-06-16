defmodule Prizmo.TcgEngine.Game.SupportedDeckActions do
  @moduledoc false

  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Prizmo.TcgEngine.SupportedDecks

  @supported_deck_fields [
    deck_key: [type: :string, allow_nil?: false],
    name: [type: :string, allow_nil?: false],
    source_url: [type: :string, allow_nil?: false],
    card_count: [type: :integer, allow_nil?: false],
    unique_card_count: [type: :integer, allow_nil?: false]
  ]

  @open_deck_card_fields [
    card_id: [type: :string, allow_nil?: false],
    count: [type: :integer, allow_nil?: false]
  ]

  @supported_deck_blueprint_fields @supported_deck_fields ++
                                     [
                                       counts: [
                                         type: {:array, :map},
                                         allow_nil?: false,
                                         constraints: [items: [fields: @open_deck_card_fields]]
                                       ]
                                     ]

  actions do
    action :list_supported_decks, {:array, :map} do
      description "List supported deck fixtures that can create TCG engine games."

      constraints items: [fields: @supported_deck_fields]

      run fn _input, _context ->
        {:ok, SupportedDecks.list()}
      end
    end

    action :get_supported_deck_blueprint, :map do
      description "Fetch full blueprint (including card counts) for a supported deck key. Used by the SPA to preload editable decklists for regular games."

      constraints fields: @supported_deck_blueprint_fields

      argument :deck_key, :string, allow_nil?: false

      run fn input, _context ->
        SupportedDecks.fetch_blueprint(input.arguments.deck_key)
      end
    end
  end
end
