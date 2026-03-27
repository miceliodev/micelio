defmodule Micelio.Repo.Migrations.RemoveLlmModelFromRepositories do
  use Ecto.Migration

  def change do
    alter table(:repositories) do
      remove :llm_model, :string, null: false, default: "gpt-4.1-mini"
    end
  end
end
