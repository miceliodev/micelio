defmodule Micelio.Repo.Migrations.DropRepositoryStars do
  use Ecto.Migration

  def up do
    drop_if_exists index(:repository_stars, [:repository_id])
    drop_if_exists index(:repository_stars, [:user_id])

    execute("DROP INDEX IF EXISTS repository_stars_user_id_repository_id_index")

    drop_if_exists table(:repository_stars)
  end

  def down do
    create table(:repository_stars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :repository_id, references(:repositories, on_delete: :delete_all, type: :binary_id)
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:repository_stars, [:repository_id])
    create index(:repository_stars, [:user_id])

    create unique_index(:repository_stars, [:user_id, :repository_id],
             name: :repository_stars_user_id_repository_id_index
           )
  end
end
