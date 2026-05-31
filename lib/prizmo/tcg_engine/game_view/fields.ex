defmodule Prizmo.TcgEngine.GameView.Fields do
  @moduledoc false

  @base_card_summary_fields [
    id: [type: :uuid, allow_nil?: false],
    instance_id: [type: :string, allow_nil?: false],
    card_id: [type: :string, allow_nil?: false],
    name: [type: :string, allow_nil?: false],
    image: [type: :string],
    category: [type: :string],
    stage: [type: :string],
    owner_player_id: [type: :string, allow_nil?: false],
    zone: [type: :string, allow_nil?: false],
    position: [type: :integer, allow_nil?: false],
    damage: [type: :integer, allow_nil?: false],
    status: [type: :string],
    attached_to_card_instance_id: [type: :uuid],
    evolves_from_card_instance_id: [type: :uuid],
    turn_entered_play: [type: :integer]
  ]

  @attached_card_summary_fields @base_card_summary_fields

  @card_summary_fields @base_card_summary_fields ++
                         [
                           attached_cards: [
                             type: {:array, :map},
                             allow_nil?: false,
                             constraints: [items: [fields: @attached_card_summary_fields]]
                           ]
                         ]

  @setup_view_fields [
    id: [type: :uuid, allow_nil?: false],
    status: [type: :string, allow_nil?: false]
  ]

  @attack_copy_choice_fields [
    attack_id: [type: :string, allow_nil?: false],
    attack_name: [type: :string, allow_nil?: false],
    attack_damage: [type: :string],
    attack_effect_type: [type: :string]
  ]

  @turn_view_fields [
    id: [type: :uuid, allow_nil?: false],
    turn_number: [type: :integer, allow_nil?: false],
    active_player_id: [type: :string, allow_nil?: false],
    status: [type: :string, allow_nil?: false],
    visible: [type: :boolean, allow_nil?: false],
    pending_attack_id: [type: :string],
    pending_attack_effect_type: [type: :string],
    pending_attack_requires_switch_target: [type: :boolean, allow_nil?: false],
    pending_attack_requires_discarded_energy: [type: :boolean, allow_nil?: false],
    pending_attack_requires_returned_energy: [type: :boolean, allow_nil?: false],
    pending_attack_requires_shuffled_energy: [type: :boolean, allow_nil?: false],
    pending_attack_requires_bench_damage_target: [type: :boolean, allow_nil?: false],
    pending_attack_requires_bench_damage_counters: [type: :boolean, allow_nil?: false],
    pending_attack_requires_coin_result: [type: :boolean, allow_nil?: false],
    pending_attack_requires_heads_count: [type: :boolean, allow_nil?: false],
    pending_attack_requires_copied_attack: [type: :boolean, allow_nil?: false],
    pending_attack_copy_choices: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @attack_copy_choice_fields]]
    ],
    pending_attacker_card_instance_id: [type: :uuid],
    pending_defender_card_instance_id: [type: :uuid]
  ]

  @player_view_fields [
    player_id: [type: :string, allow_nil?: false],
    deck_key: [type: :string, allow_nil?: false],
    energy_attached_this_turn: [type: :boolean, allow_nil?: false],
    supporter_played_this_turn: [type: :boolean, allow_nil?: false],
    retreated_this_turn: [type: :boolean, allow_nil?: false],
    ace_spec_played_this_game: [type: :boolean, allow_nil?: false],
    deck_count: [type: :integer, allow_nil?: false],
    hand_count: [type: :integer, allow_nil?: false],
    prize_count: [type: :integer, allow_nil?: false],
    discard_count: [type: :integer, allow_nil?: false],
    active: [type: :map, constraints: [fields: @card_summary_fields]],
    bench: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @card_summary_fields]]
    ],
    hand: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @card_summary_fields]]
    ],
    discard: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @card_summary_fields]]
    ]
  ]

  @event_view_fields [
    id: [type: :uuid, allow_nil?: false],
    index: [type: :integer, allow_nil?: false],
    type: [type: :string, allow_nil?: false],
    player_id: [type: :string],
    turn_id: [type: :uuid]
  ]

  @prompt_view_fields [
    id: [type: :uuid, allow_nil?: false],
    prompt_type: [type: :string, allow_nil?: false],
    status: [type: :string, allow_nil?: false],
    player_id: [type: :string, allow_nil?: false],
    payload: [type: :map, allow_nil?: false]
  ]

  @action_affordance_fields [
    key: [type: :string, allow_nil?: false],
    label: [type: :string, allow_nil?: false],
    kind: [type: :string, allow_nil?: false],
    player_id: [type: :string, allow_nil?: false],
    source_card_instance_ids: [type: {:array, :uuid}, allow_nil?: false],
    target_card_instance_ids: [type: {:array, :uuid}, allow_nil?: false],
    required_source_count: [type: :integer, allow_nil?: false],
    attack_id: [type: :string],
    attack_name: [type: :string],
    attack_cost: [type: {:array, :string}, allow_nil?: false],
    attack_damage: [type: :string],
    prompt_ids: [type: {:array, :uuid}, allow_nil?: false],
    choice_keys: [type: {:array, :string}, allow_nil?: false],
    note: [type: :string]
  ]

  @game_state_fields [
    game_id: [type: :uuid, allow_nil?: false],
    viewer_player_id: [type: :string, allow_nil?: false],
    status: [type: :string, allow_nil?: false],
    flow_state: [type: :string, allow_nil?: false],
    active_player_id: [type: :string, allow_nil?: false],
    first_player_id: [type: :string, allow_nil?: false],
    winner_player_id: [type: :string],
    coin_toss_calling_player_id: [type: :string],
    coin_toss_call: [type: :string],
    coin_toss_result: [type: :string],
    coin_toss_winner_player_id: [type: :string],
    starting_player_chosen_by_player_id: [type: :string],
    cursor_index: [type: :integer, allow_nil?: false],
    latest_event_index: [type: :integer, allow_nil?: false],
    awaiting_prompt_player_ids: [type: {:array, :string}, allow_nil?: false],
    setup: [type: :map, constraints: [fields: @setup_view_fields]],
    current_turn: [type: :map, constraints: [fields: @turn_view_fields]],
    action_affordances: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @action_affordance_fields]]
    ],
    stadium: [type: :map, constraints: [fields: @card_summary_fields]],
    players: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @player_view_fields]]
    ],
    events: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @event_view_fields]]
    ],
    prompts: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @prompt_view_fields]]
    ]
  ]

  def game_state_fields, do: @game_state_fields
end
