defmodule Prizmo.TcgEngine.Cards.Cost do
  @moduledoc false

  @enforce_keys [:key, :type]
  defstruct [:key, :type, params: %{}]
end
