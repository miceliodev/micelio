defmodule Micelio.Repo.Migrations.CreateAiTokenContributions do
  use Ecto.Migration

  def change do
    create table(:ai_token_contributions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :integer, null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ai_token_contributions, [:project_id])
    create index(:ai_token_contributions, [:user_id])
    create index(:ai_token_contributions, [:inserted_at])
  end
end
