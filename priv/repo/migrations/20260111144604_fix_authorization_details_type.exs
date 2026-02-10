defmodule Micelio.Repo.Migrations.FixAuthorizationDetailsType do
  use Ecto.Migration

  def up do
    if sqlite?() do
      :ok
    else
      execute "ALTER TABLE oauth_tokens ALTER COLUMN authorization_details TYPE jsonb USING authorization_details::jsonb"
    end
  end

  def down do
    if sqlite?() do
      :ok
    else
      execute "ALTER TABLE oauth_tokens ALTER COLUMN authorization_details TYPE text"
    end
  end

  defp sqlite? do
    repo().__adapter__() == Ecto.Adapters.SQLite3
  end
end
