defmodule Micelio.Repo.Migrations.CreateFediverseFollowers do
  use Ecto.Migration

  def change do
    create table(:fediverse_followers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor, :string, null: false
      add :inbox, :string

      timestamps(type: :utc_datetime)
    end

    create index(:fediverse_followers, [:account_id])

    create unique_index(:fediverse_followers, [:account_id, :actor],
             name: :fediverse_followers_account_id_actor_index
           )
  end
end
