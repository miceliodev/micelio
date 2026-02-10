defmodule Micelio.Repo.Migrations.MoveLlmColumnsToAccounts do
  use Ecto.Migration

  def change do
    # Add LLM columns to accounts table
    alter table(:accounts) do
      add :llm_models, {:array, :string}
      add :llm_default_model, :string
    end

    # Migrate data from organizations to their accounts
    execute """
            UPDATE accounts
            SET llm_models = (
              SELECT llm_models FROM organizations
              WHERE organizations.id = accounts.organization_id
            ),
            llm_default_model = (
              SELECT llm_default_model FROM organizations
              WHERE organizations.id = accounts.organization_id
            )
            WHERE accounts.organization_id IS NOT NULL
            """,
            # Rollback: copy data back to organizations
            """
            UPDATE organizations
            SET llm_models = (
              SELECT llm_models FROM accounts
              WHERE accounts.organization_id = organizations.id
            ),
            llm_default_model = (
              SELECT llm_default_model FROM accounts
              WHERE accounts.organization_id = organizations.id
            )
            """

    # Remove LLM columns from organizations table
    alter table(:organizations) do
      remove :llm_models, {:array, :string}
      remove :llm_default_model, :string
    end
  end
end
