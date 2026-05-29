defmodule Prizmo.TcgEngine.SetupStore do
  @moduledoc false

  alias Prizmo.TcgEngine.Setup

  require Ash.Query

  def get_setup(game_id) do
    case maybe_get_setup(game_id) do
      {:ok, %Setup{} = setup} -> {:ok, setup}
      {:ok, nil} -> {:error, :setup_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  def require_setup_status(game_id, status) do
    with {:ok, setup} <- get_setup(game_id) do
      if setup.status == status do
        {:ok, setup}
      else
        {:error, {:invalid_setup_status, setup.status, status}}
      end
    end
  end

  defp maybe_get_setup(game_id) do
    Setup
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.read_one()
  end
end
