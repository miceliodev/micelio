defmodule Micelio.Repo.Migrations.CreateOrganizationMemberships do
  use Ecto.Migration

  def change do
    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:organization_memberships, [:organization_id])
    create index(:organization_memberships, [:user_id])

    create unique_index(:organization_memberships, [:user_id, :organization_id],
             name: :organization_memberships_user_id_organization_id_index
           )
  end
end
