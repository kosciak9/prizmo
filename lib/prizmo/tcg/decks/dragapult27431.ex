defmodule Prizmo.Tcg.Decks.Dragapult27431 do
  @moduledoc """
  Static decklist for Limitless deck 27431.
  """

  use Prizmo.Tcg.Decklist

  deck(
    id: "27431",
    name: "Dragapult",
    source_url: "https://limitlesstcg.com/decks/list/27431",
    counts: [
      # Keep one Basic, Ultra Ball, and Energy early so browser playtests can exercise
      # prompt, Bench, Attach Energy, and End Turn flows without many draw cycles.
      # The fixture still preserves source counts.
      {"PFL-014", 1},
      {"MEG-131", 4},
      {"MEE-002", 3},
      {"TWM-128", 4},
      {"TWM-129", 4},
      {"TWM-130", 3},
      {"TWM-095", 2},
      {"ASC-016", 2},
      {"ASC-142", 1},
      {"POR-062", 1},
      {"MEG-119", 4},
      {"SCR-133", 3},
      {"MEG-114", 3},
      {"POR-076", 1},
      {"PFL-087", 1},
      {"POR-071", 4},
      {"TEF-144", 4},
      {"POR-081", 4},
      {"ASC-196", 2},
      {"TWM-165", 1},
      {"MEG-127", 1},
      {"DRI-180", 1},
      {"MEE-005", 3},
      {"MEE-007", 3}
    ],
    validate: true
  )
end
