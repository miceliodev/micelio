defmodule Micelio.Repo do
  use Ecto.Repo,
    otp_app: :micelio,
    adapter: Ecto.Adapters.Postgres
end
