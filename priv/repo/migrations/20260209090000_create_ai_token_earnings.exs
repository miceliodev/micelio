defmodule Micelio.Repo.Migrations.CreateAiTokenEarnings do
  use Ecto.Migration

  def change do
    create table(:ai_token_earnings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :bigint, null: false
      add :reason, :string, null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :prompt_request_id,
          references(:prompt_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ai_token_earnings, [:project_id])
    create index(:ai_token_earnings, [:user_id])
    create index(:ai_token_earnings, [:inserted_at])
    create unique_index(:ai_token_earnings, [:prompt_request_id])
  end
end
