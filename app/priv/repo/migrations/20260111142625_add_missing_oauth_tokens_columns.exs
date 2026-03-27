defmodule Micelio.Repo.Migrations.AddMissingOauthTokensColumns do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :refresh_token, :string
      add :authorization_details, :text
      add :c_nonce, :string
      add :code_challenge_method, :string
    end
  end
end
