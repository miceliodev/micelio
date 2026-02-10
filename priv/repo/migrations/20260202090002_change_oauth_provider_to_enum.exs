defmodule Micelio.Repo.Migrations.ChangeOauthProviderToEnum do
  use Ecto.Migration

  @moduledoc """
  This migration is a no-op for the database schema since Ecto.Enum
  stores atom values as strings (e.g., :github becomes "github").

  The existing data already contains "github" and "gitlab" strings,
  which are compatible with the new Ecto.Enum definition.

  This migration exists for documentation purposes and to ensure
  the migration history reflects the schema change.
  """

  def change do
    # Ecto.Enum stores atoms as their string representation
    # e.g., :github is stored as "github" in the database
    # Since existing data already has "github" and "gitlab" strings,
    # no data migration is needed.
    :ok
  end
end
