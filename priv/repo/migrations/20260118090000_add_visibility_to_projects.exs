defmodule Micelio.Repo.Migrations.AddVisibilityToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :visibility, :string, null: false, default: "private"
    end
  end
end
