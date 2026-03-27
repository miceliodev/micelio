defmodule Micelio.Repo.Migrations.AddLlmModelsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :llm_models, {:array, :string}
      add :llm_default_model, :string
    end
  end
end
