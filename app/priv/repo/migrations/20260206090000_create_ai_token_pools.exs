defmodule Micelio.Repo.Migrations.CreateAiTokenPools do
  use Ecto.Migration

  def change do
    create table(:ai_token_pools, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :balance, :bigint, null: false, default: 0
      add :reserved, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_token_pools, [:project_id])
  end
end
