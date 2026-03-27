defmodule Micelio.Repo.Migrations.CreateProjectStars do
  use Ecto.Migration

  def change do
    create table(:project_stars, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:project_stars, [:project_id])
    create index(:project_stars, [:user_id])

    create unique_index(:project_stars, [:user_id, :project_id],
             name: :project_stars_user_id_project_id_index
           )
  end
end
