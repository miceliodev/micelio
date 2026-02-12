defmodule Micelio.Repo.Migrations.AddStatusToPromptRequests do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :status, :string, null: false, default: "open"
    end
  end
end
