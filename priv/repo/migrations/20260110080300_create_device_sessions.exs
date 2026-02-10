defmodule Micelio.Repo.Migrations.CreateDeviceSessions do
  use Ecto.Migration

  def change do
    create table(:device_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, :string, null: false
      add :client_name, :string, null: false
      add :device_name, :string
      add :refresh_token, :string, null: false
      add :access_token, :string
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:device_sessions, [:user_id])
    create index(:device_sessions, [:client_id])
    create index(:device_sessions, [:revoked_at])
  end
end
