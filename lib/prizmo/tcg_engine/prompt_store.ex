defmodule Prizmo.TcgEngine.PromptStore do
  @moduledoc false

  alias Prizmo.TcgEngine.Prompt

  require Ash.Query

  def get_prompt(game_id, prompt_id) do
    case Prompt
         |> Ash.Query.filter(game_id == ^game_id and id == ^prompt_id)
         |> Ash.read_one() do
      {:ok, %Prompt{} = prompt} -> {:ok, prompt}
      {:ok, nil} -> {:error, :prompt_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
