defmodule Micelio.Repo.Migrations.AddValidationIterationsToPromptRequests do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :validation_iterations, :integer, default: 0, null: false
    end
  end
end
