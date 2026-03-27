defmodule Micelio.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bio, :string, size: 160
      add :website_url, :string
      add :twitter_url, :string
      add :github_url, :string
      add :gitlab_url, :string
      add :mastodon_url, :string
      add :linkedin_url, :string
    end
  end
end
