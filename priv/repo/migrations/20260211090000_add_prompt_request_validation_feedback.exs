defmodule Micelio.Repo.Migrations.AddPromptRequestValidationFeedback do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :validation_feedback, :text
    end
  end
end
