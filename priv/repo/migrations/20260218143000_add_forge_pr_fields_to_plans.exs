defmodule Micelio.Repo.Migrations.AddForgePrFieldsToPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :forge_branch_name, :string, size: 255
      add :forge_pr_provider, :string, size: 32
      add :forge_pr_number, :integer
      add :forge_pr_url, :string, size: 1024
      add :forge_pr_state, :string, size: 32
      add :forge_pr_draft, :boolean, default: true, null: false
      add :forge_pr_synced_at, :utc_datetime
      add :forge_pr_metadata, :map, default: %{}, null: false
    end

    create index(:plans, [:forge_pr_provider, :forge_pr_number])
  end
end
