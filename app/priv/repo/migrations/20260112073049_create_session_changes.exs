defmodule Micelio.Repo.Migrations.CreateSessionChanges do
  use Ecto.Migration

  def change do
    create table(:session_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :file_path, :text, null: false
      # "added", "modified", "deleted"
      add :change_type, :string, null: false
      # S3/local storage key for content
      add :storage_key, :text
      # For small files, store inline
      add :content, :text
      # lines_added, lines_removed, etc.
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:session_changes, [:session_id])
    create index(:session_changes, [:change_type])
    create index(:session_changes, [:file_path])
  end
end
