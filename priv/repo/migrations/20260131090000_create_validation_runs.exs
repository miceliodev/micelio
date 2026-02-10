defmodule Micelio.Repo.Migrations.CreateValidationRuns do
  use Ecto.Migration

  def change do
    create table(:validation_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :prompt_request_id,
          references(:prompt_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "pending"
      add :provider, :string
      add :instance_ref, :map
      add :check_results, :map, null: false, default: %{}
      add :metrics, :map, null: false, default: %{}
      add :resource_usage, :map, null: false, default: %{}
      add :coverage_delta, :float
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:validation_runs, [:prompt_request_id])
    create index(:validation_runs, [:status])
    create index(:validation_runs, [:inserted_at])
  end
end
