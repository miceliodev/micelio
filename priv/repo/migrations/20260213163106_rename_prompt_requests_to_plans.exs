defmodule Micelio.Repo.Migrations.RenamePromptRequestsToPlans do
  use Ecto.Migration

  def change do
    # Part A: Rename tables
    rename table(:prompt_requests), to: table(:plans)
    rename table(:prompt_suggestions), to: table(:plan_suggestions)
    rename table(:prompt_templates), to: table(:plan_templates)

    # Part A: Rename foreign key columns
    rename table(:plans), :parent_prompt_request_id, to: :parent_plan_id
    rename table(:plans), :prompt_template_id, to: :plan_template_id
    rename table(:plan_suggestions), :prompt_request_id, to: :plan_id
    rename table(:ai_token_earnings), :prompt_request_id, to: :plan_id
    rename table(:ai_token_task_budgets), :prompt_request_id, to: :plan_id
    rename table(:validation_runs), :prompt_request_id, to: :plan_id

    # Part B: Create plan_messages table
    create table(:plan_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plan_id, references(:plans, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, size: 20, null: false
      add :content, :text
      add :model, :string, size: 120
      add :author, :string, size: 255
      add :agent, :string, size: 50
      add :tool_name, :string, size: 255
      add :tool_input, :map
      add :tool_output, :map
      add :status, :string, size: 20, null: false, default: "complete"
      add :token_count, :integer
      add :sequence, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:plan_messages, [:plan_id])
    create index(:plan_messages, [:plan_id, :sequence])

    # Part C: Add agent tracking columns to plans
    alter table(:plans) do
      add :agent, :string, size: 50
      add :agent_model, :string, size: 120
      add :agent_status, :string, size: 20, default: "idle"
    end
  end
end
