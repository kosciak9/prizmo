defmodule Prizmo.Accounts do
  @moduledoc false
  use Ash.Domain, otp_app: :prizmo, extensions: [AshAdmin.Domain, AshTypescript.Rpc]

  alias Prizmo.Accounts.User

  admin do
    show? true
  end

  typescript_rpc do
    resource User do
      rpc_action :list_users, :read
    end
  end

  resources do
    resource Prizmo.Accounts.Token
    resource User
  end
end
