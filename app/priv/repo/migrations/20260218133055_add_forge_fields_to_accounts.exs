defmodule Micelio.Repo.Migrations.AddForgeFieldsToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :forge_provider, :string, size: 20
      add :forge_host, :string, size: 120
    end
  end
end
