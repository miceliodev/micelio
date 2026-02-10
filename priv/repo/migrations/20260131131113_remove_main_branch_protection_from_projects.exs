defmodule Micelio.Repo.Migrations.RemoveMainBranchProtectionFromProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      remove :protect_main_branch, :boolean, default: false, null: false
    end
  end
end
