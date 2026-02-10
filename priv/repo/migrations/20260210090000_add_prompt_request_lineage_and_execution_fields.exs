defmodule Micelio.Repo.Migrations.AddPromptRequestLineageAndExecutionFields do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :parent_prompt_request_id,
          references(:prompt_requests, type: :binary_id, on_delete: :nilify_all)

      add :execution_environment, :map
      add :execution_duration_ms, :integer
    end

    create index(:prompt_requests, [:parent_prompt_request_id])
  end
end
