defmodule Micelio.Repo.Migrations.AddLlmProviderAndApiKeyToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :llm_provider, :string, size: 40
      add :llm_api_key_encrypted, :binary
    end
  end
end
