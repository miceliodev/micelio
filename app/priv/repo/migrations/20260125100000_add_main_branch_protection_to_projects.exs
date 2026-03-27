defmodule Micelio.Repo.Migrations.AddMainBranchProtectionToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :protect_main_branch, :boolean, default: false, null: false
    end
  end
end
