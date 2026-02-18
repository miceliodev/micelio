defmodule Micelio.Repo.Migrations.AddSandboxProviderToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :sandbox_provider, :string, size: 20, default: "docker"
    end
  end
end
