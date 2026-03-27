defmodule Micelio.Repo.Migrations.AddLlmModelToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :llm_model, :string, null: false, default: "gpt-4.1-mini"
    end
  end
end
