defmodule Micelio.Repo.Migrations.AddSandboxFieldsToPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :sandbox_workspace_id, :string
      add :sandbox_provider, :string, size: 20
      add :sandbox_status, :string, size: 20, default: "none"
      add :sandbox_started_at, :utc_datetime
      add :sandbox_expires_at, :utc_datetime
      add :sandbox_metadata, :map, default: %{}
    end

    create index(:plans, [:sandbox_status])
    create index(:plans, [:user_id, :sandbox_status])
  end
end
