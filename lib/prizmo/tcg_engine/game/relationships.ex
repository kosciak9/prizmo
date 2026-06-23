defmodule Prizmo.TcgEngine.Game.Relationships do
  @moduledoc false

  use Spark.Dsl.Fragment, of: Ash.Resource

  relationships do
    has_many :players, Prizmo.TcgEngine.GamePlayer
    has_many :turns, Prizmo.TcgEngine.Turn
    has_many :cards, Prizmo.TcgEngine.CardInstance
    has_many :events, Prizmo.TcgEngine.GameEvent
    has_many :snapshots, Prizmo.TcgEngine.GameSnapshot
    has_many :prompts, Prizmo.TcgEngine.Prompt
    has_one :setup, Prizmo.TcgEngine.Setup
  end
end
