defmodule Micelio.Repo.Migrations.CreateErrors do
  use Ecto.Migration

  def change do
    create table(:errors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fingerprint, :string, null: false
      add :kind, :string, null: false
      add :message, :text, null: false
      add :stacktrace, :text
      add :metadata, :map, null: false, default: %{}
      add :context, :map, null: false, default: %{}
      add :severity, :string, null: false, default: "error"
      add :occurred_at, :utc_datetime, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :occurrence_count, :integer, null: false, default: 1
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:errors, [:fingerprint])
    create index(:errors, [:kind])
    create index(:errors, [:severity])
    create index(:errors, [:occurred_at])
    create index(:errors, [:resolved_at])
  end
end
