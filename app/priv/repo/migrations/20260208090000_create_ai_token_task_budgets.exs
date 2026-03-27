defmodule Micelio.Repo.Migrations.CreateAiTokenTaskBudgets do
  use Ecto.Migration

  def change do
    create table(:ai_token_task_budgets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :token_pool_id, references(:ai_token_pools, type: :binary_id, on_delete: :delete_all),
        null: false

      add :prompt_request_id,
          references(:prompt_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :amount, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:ai_token_task_budgets, [:token_pool_id])
    create unique_index(:ai_token_task_budgets, [:prompt_request_id])
  end
end
