defmodule Micelio.Repo.Migrations.AddPromptRequestTransparencyFields do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :origin, :string, null: false, default: "ai_generated"
      add :model_version, :string
      add :token_count, :integer
      add :generated_at, :utc_datetime
      add :attestation, :map, null: false, default: %{}
    end

    create index(:prompt_requests, [:origin])
    create index(:prompt_requests, [:generated_at])
  end
end
