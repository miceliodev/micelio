defmodule Micelio.Repo.Migrations.CreateErrorRetentionSettings do
  use Ecto.Migration

  def change do
    create table(:error_retention_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :resolved_retention_days, :integer, default: 30, null: false
      add :unresolved_retention_days, :integer, default: 90, null: false
      add :archive_enabled, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
