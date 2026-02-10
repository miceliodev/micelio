defmodule Micelio.Repo.Migrations.AddPromptRegistryAndTemplates do
  use Ecto.Migration

  def change do
    create table(:prompt_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :prompt, :text, null: false
      add :system_prompt, :text, null: false
      add :category, :string
      add :approved_at, :utc_datetime

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:prompt_templates, [:name])
    create index(:prompt_templates, [:approved_at])
    create index(:prompt_templates, [:created_by_id])
    create index(:prompt_templates, [:approved_by_id])

    alter table(:prompt_requests) do
      add :prompt_template_id,
          references(:prompt_templates, type: :binary_id, on_delete: :nilify_all)

      add :curated_at, :utc_datetime
      add :curated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:prompt_requests, [:prompt_template_id])
    create index(:prompt_requests, [:curated_at])
    create index(:prompt_requests, [:curated_by_id])
  end
end
