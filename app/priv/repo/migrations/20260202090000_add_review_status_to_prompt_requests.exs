defmodule Micelio.Repo.Migrations.AddReviewStatusToPromptRequests do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :review_status, :string, null: false, default: "pending"
      add :reviewed_at, :utc_datetime
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:prompt_requests, [:review_status])
    create index(:prompt_requests, [:reviewed_by_id])
  end
end
