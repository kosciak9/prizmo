defmodule Prizmo.TcgEngine.Cards.Effect do
  @moduledoc false

  @enforce_keys [:key, :type]
  defstruct [:key, :type, params: %{}]
end
