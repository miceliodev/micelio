defmodule Micelio.Repo.Migrations.AddForgeFieldsToRepositories do
  use Ecto.Migration

  def change do
    alter table(:repositories) do
      add :forge_provider, :string, size: 20
      add :forge_host, :string, size: 120
      add :forge_owner, :string, size: 255
      add :forge_repo, :string, size: 255
      add :forge_external_id, :string, size: 255
      add :forge_default_branch, :string, size: 255
      add :mirror_status, :string, size: 20, default: "pending"
      add :mirror_last_synced_at, :utc_datetime
    end

    create index(:repositories, [:forge_provider])
    create index(:repositories, [:forge_host])
    create index(:repositories, [:mirror_status])

    create unique_index(
             :repositories,
             [:forge_host, "lower(forge_owner)", "lower(forge_repo)"],
             name: :repositories_forge_host_owner_repo_index,
             where:
               "forge_host IS NOT NULL AND forge_owner IS NOT NULL AND forge_repo IS NOT NULL"
           )
  end
end
