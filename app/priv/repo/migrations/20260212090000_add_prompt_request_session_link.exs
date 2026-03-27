defmodule Micelio.Repo.Migrations.AddPromptRequestSessionLink do
  use Ecto.Migration

  def change do
    alter table(:prompt_requests) do
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
    end

    create unique_index(:prompt_requests, [:session_id])
  end
end
