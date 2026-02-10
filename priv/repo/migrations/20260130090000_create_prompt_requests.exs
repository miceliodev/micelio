defmodule Micelio.Repo.Migrations.CreatePromptRequests do
  use Ecto.Migration

  def change do
    create table(:prompt_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :prompt, :text, null: false
      add :result, :text, null: false
      add :model, :string, null: false
      add :system_prompt, :text, null: false
      add :conversation, :map, null: false, default: %{}

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:prompt_requests, [:project_id])
    create index(:prompt_requests, [:user_id])
    create index(:prompt_requests, [:inserted_at])

    create table(:prompt_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :suggestion, :text, null: false

      add :prompt_request_id,
          references(:prompt_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:prompt_suggestions, [:prompt_request_id])
    create index(:prompt_suggestions, [:user_id])
    create index(:prompt_suggestions, [:inserted_at])
  end
end
