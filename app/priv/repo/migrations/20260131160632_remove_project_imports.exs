defmodule Micelio.Repo.Migrations.RemoveProjectImports do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:project_imports))
  end
end
