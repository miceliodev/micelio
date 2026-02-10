defmodule Micelio.Repo.Migrations.CreatePasskeys do
  use Ecto.Migration

  def change do
    create table(:passkeys, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:credential_id, :binary, null: false)
      add(:public_key, :binary, null: false)
      add(:sign_count, :integer, null: false, default: 0)
      add(:name, :string, null: false)
      add(:last_used_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:passkeys, [:credential_id]))
    create(index(:passkeys, [:user_id]))
  end
end
