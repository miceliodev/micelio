defmodule Micelio.Repo.Migrations.AddNumberAndDescriptionToPromptRequests do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :number, :integer
      add :description, :text
    end

    # Make complex fields nullable for simple prompt requests
    alter table(:prompt_requests) do
      modify :prompt, :text, null: true
      modify :result, :text, null: true
      modify :model, :string, null: true
      modify :system_prompt, :text, null: true
      modify :conversation, :map, null: true
    end

    create unique_index(:prompt_requests, [:repository_id, :number])
  end
end
