defmodule Micelio.Repo.Migrations.CreateProjectImports do
  use Ecto.Migration

  def change do
    create table(:project_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :source_url, :string, null: false
      add :source_forge, :string
      add :status, :string, null: false, default: "queued"
      add :stage, :string, null: false, default: "metadata"
      add :error_message, :text
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:project_imports, [:project_id])
    create index(:project_imports, [:status])
    create index(:project_imports, [:inserted_at])
  end
end
