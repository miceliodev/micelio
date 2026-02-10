defmodule Micelio.Repo.Migrations.CreateProjectAccessTokens do
  use Ecto.Migration

  def change do
    create table(:project_access_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :token_prefix, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_access_tokens, [:token_hash])
    create index(:project_access_tokens, [:project_id])
    create index(:project_access_tokens, [:user_id])
  end
end
