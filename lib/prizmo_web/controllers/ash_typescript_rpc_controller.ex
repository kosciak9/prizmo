defmodule PrizmoWeb.AshTypescriptRpcController do
  use PrizmoWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:prizmo, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:prizmo, conn, params)
    json(conn, result)
  end
end
