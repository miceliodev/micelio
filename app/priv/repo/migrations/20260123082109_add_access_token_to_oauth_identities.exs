defmodule Micelio.Repo.Migrations.AddAccessTokenToOauthIdentities do
  use Ecto.Migration

  def change do
    alter table(:oauth_identities) do
      add :access_token_encrypted, :binary
    end
  end
end
