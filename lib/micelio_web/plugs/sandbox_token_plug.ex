defmodule MicelioWeb.Plugs.SandboxTokenPlug do
  @moduledoc """
  Authenticates sandbox module requests using per-sandbox bearer tokens.

  Deno sends the token via `Authorization: Bearer <token>` header,
  configured through the `DENO_AUTH_TOKENS` environment variable.
  Only plans with `sandbox_status == "running"` are matched.
  """

  import Plug.Conn
  import Ecto.Query, warn: false

  alias Micelio.Plans.Plan
  alias Micelio.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- fetch_bearer_token(conn),
         %Plan{} = plan <- find_plan_by_sandbox_token(token) do
      assign(conn, :sandbox_plan, plan)
    else
      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      ["bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end

  defp find_plan_by_sandbox_token(token) do
    Plan
    |> where([p], p.sandbox_status == "running")
    |> where([p], fragment("? ->> 'sandbox_token' = ?", p.sandbox_metadata, ^token))
    |> limit(1)
    |> Repo.one()
  end
end
