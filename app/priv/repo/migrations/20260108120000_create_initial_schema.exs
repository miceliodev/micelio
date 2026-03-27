defmodule Micelio.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  def change do
    # Organizations table
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Accounts table
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, ["lower(handle)"], name: :accounts_handle_index)

    # Users table
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, ["lower(email)"], name: :users_email_index)

    # Add account ownership columns after users table exists
    alter table(:accounts) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:accounts, [:user_id])
    create index(:accounts, [:organization_id])

    # Tokens table

    create table(:tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :purpose, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:tokens, [:token])
    create index(:tokens, [:user_id])
    create index(:tokens, [:expires_at])
    create index(:tokens, [:purpose])
  end
end
