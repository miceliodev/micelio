defmodule Micelio.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :name, :string, null: false
      add :description, :string

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:account_id])

    create unique_index(:projects, [:account_id, "lower(handle)"],
             name: :projects_account_handle_index
           )
  end
end
