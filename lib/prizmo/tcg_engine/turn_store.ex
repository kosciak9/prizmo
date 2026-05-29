defmodule Prizmo.TcgEngine.TurnStore do
  @moduledoc false

  alias Prizmo.TcgEngine.Turn

  require Ash.Query

  def list_all_turns(game_id) do
    Turn
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.Query.sort(turn_number: :asc)
    |> Ash.read()
  end

  def latest_turn(game_id) do
    Turn
    |> Ash.Query.filter(game_id == ^game_id and visible? == true)
    |> Ash.Query.sort(turn_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
  end

  def current_turn(game_id) do
    case latest_turn(game_id) do
      {:ok, %Turn{} = turn} -> {:ok, turn}
      {:ok, nil} -> {:error, :turn_not_started}
      {:error, reason} -> {:error, reason}
    end
  end
end
