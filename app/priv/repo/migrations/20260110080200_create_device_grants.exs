defmodule Micelio.Repo.Migrations.CreateDeviceGrants do
  use Ecto.Migration

  def change do
    create table(:device_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_code, :string, null: false
      add :user_code, :string, null: false
      add :client_id, :string, null: false
      add :scope, :string
      add :device_name, :string
      add :expires_at, :utc_datetime, null: false
      add :interval, :integer, null: false
      add :last_polled_at, :utc_datetime
      add :approved_at, :utc_datetime
      add :used_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_grants, [:device_code])
    create unique_index(:device_grants, [:user_code])
    create index(:device_grants, [:client_id])
    create index(:device_grants, [:user_id])
  end
end
