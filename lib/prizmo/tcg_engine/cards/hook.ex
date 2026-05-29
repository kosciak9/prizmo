defmodule Prizmo.TcgEngine.Cards.Hook do
  @moduledoc false

  @enforce_keys [:key, :phase, :priority, :scope, :resolver]
  defstruct [:key, :phase, :priority, :scope, :resolver, meta: %{}]
end
