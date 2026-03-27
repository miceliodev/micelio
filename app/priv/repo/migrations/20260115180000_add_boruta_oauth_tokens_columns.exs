defmodule Micelio.Repo.Migrations.AddBorutaOauthTokensColumns do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :presentation_definition, :text
      add :previous_token, :string
      add :previous_code, :string
      add :nonce, :string
      add :refresh_token_revoked_at, :utc_datetime_usec
      add :tx_code, :string
      add :code_challenge_hash, :string
      add :agent_token, :string
      add :bind_data, :text
      add :bind_configuration, :text
      add :public_client_id, :string
    end
  end
end
