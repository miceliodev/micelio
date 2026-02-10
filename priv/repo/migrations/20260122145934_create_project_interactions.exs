defmodule Micelio.Repo.Migrations.CreateProjectInteractions do
  use Ecto.Migration

  def change do
    create table(:project_interactions) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :last_interacted_at, :utc_datetime, null: false
      add :interaction_count, :integer, null: false, default: 0
      add :last_interaction_type, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_interactions, [:user_id, :project_id])
    create index(:project_interactions, [:user_id, :last_interacted_at])
  end
end
