defmodule Prizmo.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Prizmo.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:prizmo, :token_signing_secret)
  end
end
