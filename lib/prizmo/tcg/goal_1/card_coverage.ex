defmodule Prizmo.Tcg.Goal1.CardCoverage do
  @moduledoc """
  Backward-compatible Goal 1 wrapper around the shared card coverage classifier.
  """

  alias Prizmo.Tcg.CardCoverage

  @type coverage_status :: CardCoverage.coverage_status()
  @type summary :: CardCoverage.summary()

  @doc "Returns a Goal 1 coverage summary for a single card id."
  @spec summarize(String.t()) :: summary()
  defdelegate summarize(card_id), to: CardCoverage
end
