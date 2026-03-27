defmodule Micelio.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :url, :string, null: false
      add :events, {:array, :string}, null: false, default: []
      add :secret, :string
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:webhooks, [:project_id])
    create index(:webhooks, [:active])
  end
end
