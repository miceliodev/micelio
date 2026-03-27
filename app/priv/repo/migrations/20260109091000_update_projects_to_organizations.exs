defmodule Micelio.Repo.Migrations.UpdateProjectsToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:projects, [:organization_id])

    create unique_index(:projects, [:organization_id, "lower(handle)"],
             name: :projects_organization_handle_index
           )

    drop index(:projects, [:account_id])
    drop index(:projects, [:account_id, "lower(handle)"], name: :projects_account_handle_index)

    alter table(:projects) do
      remove :account_id
    end
  end

  def down do
    alter table(:projects) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:projects, [:account_id])

    create unique_index(:projects, [:account_id, "lower(handle)"],
             name: :projects_account_handle_index
           )

    drop index(:projects, [:organization_id])

    drop index(:projects, [:organization_id, "lower(handle)"],
           name: :projects_organization_handle_index
         )

    alter table(:projects) do
      remove :organization_id
    end
  end
end
