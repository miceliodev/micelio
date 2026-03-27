defmodule Micelio.Repo.Migrations.AddUrlToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :url, :string
    end
  end
end
