defmodule Micelio.Repo.Migrations.AddForkedFromToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :forked_from_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:projects, [:forked_from_id])
  end
end
