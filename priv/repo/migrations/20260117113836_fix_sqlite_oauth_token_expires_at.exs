defmodule Micelio.Repo.Migrations.FixSqliteOauthTokenExpiresAt do
  use Ecto.Migration

  def up do
    if sqlite?() do
      execute "ALTER TABLE oauth_tokens RENAME TO oauth_tokens_old"

      execute """
      CREATE TABLE oauth_tokens (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        revoked_at TEXT,
        expires_at INTEGER,
        redirect_uri TEXT,
        state TEXT,
        scope TEXT,
        sub TEXT,
        client_id TEXT NOT NULL REFERENCES clients(id),
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        refresh_token TEXT,
        authorization_details TEXT,
        c_nonce TEXT,
        code_challenge_method TEXT,
        presentation_definition TEXT,
        previous_token TEXT,
        previous_code TEXT,
        nonce TEXT,
        refresh_token_revoked_at TEXT,
        tx_code TEXT,
        code_challenge_hash TEXT,
        agent_token TEXT,
        bind_data TEXT,
        bind_configuration TEXT,
        public_client_id TEXT
      )
      """

      execute """
      INSERT INTO oauth_tokens (
        id,
        type,
        value,
        revoked_at,
        expires_at,
        redirect_uri,
        state,
        scope,
        sub,
        client_id,
        inserted_at,
        updated_at,
        refresh_token,
        authorization_details,
        c_nonce,
        code_challenge_method,
        presentation_definition,
        previous_token,
        previous_code,
        nonce,
        refresh_token_revoked_at,
        tx_code,
        code_challenge_hash,
        agent_token,
        bind_data,
        bind_configuration,
        public_client_id
      )
      SELECT
        id,
        type,
        value,
        revoked_at,
        CAST(expires_at AS INTEGER),
        redirect_uri,
        state,
        scope,
        sub,
        client_id,
        inserted_at,
        updated_at,
        refresh_token,
        authorization_details,
        c_nonce,
        code_challenge_method,
        presentation_definition,
        previous_token,
        previous_code,
        nonce,
        refresh_token_revoked_at,
        tx_code,
        code_challenge_hash,
        agent_token,
        bind_data,
        bind_configuration,
        public_client_id
      FROM oauth_tokens_old
      """

      execute "DROP TABLE oauth_tokens_old"

      create index(:oauth_tokens, [:client_id])
      create unique_index(:oauth_tokens, [:value])
      create index(:oauth_tokens, [:type])
      create index(:oauth_tokens, [:sub])
    end
  end

  def down do
    if sqlite?() do
      execute "ALTER TABLE oauth_tokens RENAME TO oauth_tokens_old"

      execute """
      CREATE TABLE oauth_tokens (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        revoked_at TEXT,
        expires_at TEXT,
        redirect_uri TEXT,
        state TEXT,
        scope TEXT,
        sub TEXT,
        client_id TEXT NOT NULL REFERENCES clients(id),
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        refresh_token TEXT,
        authorization_details TEXT,
        c_nonce TEXT,
        code_challenge_method TEXT,
        presentation_definition TEXT,
        previous_token TEXT,
        previous_code TEXT,
        nonce TEXT,
        refresh_token_revoked_at TEXT,
        tx_code TEXT,
        code_challenge_hash TEXT,
        agent_token TEXT,
        bind_data TEXT,
        bind_configuration TEXT,
        public_client_id TEXT
      )
      """

      execute """
      INSERT INTO oauth_tokens (
        id,
        type,
        value,
        revoked_at,
        expires_at,
        redirect_uri,
        state,
        scope,
        sub,
        client_id,
        inserted_at,
        updated_at,
        refresh_token,
        authorization_details,
        c_nonce,
        code_challenge_method,
        presentation_definition,
        previous_token,
        previous_code,
        nonce,
        refresh_token_revoked_at,
        tx_code,
        code_challenge_hash,
        agent_token,
        bind_data,
        bind_configuration,
        public_client_id
      )
      SELECT
        id,
        type,
        value,
        revoked_at,
        CAST(expires_at AS TEXT),
        redirect_uri,
        state,
        scope,
        sub,
        client_id,
        inserted_at,
        updated_at,
        refresh_token,
        authorization_details,
        c_nonce,
        code_challenge_method,
        presentation_definition,
        previous_token,
        previous_code,
        nonce,
        refresh_token_revoked_at,
        tx_code,
        code_challenge_hash,
        agent_token,
        bind_data,
        bind_configuration,
        public_client_id
      FROM oauth_tokens_old
      """

      execute "DROP TABLE oauth_tokens_old"

      create index(:oauth_tokens, [:client_id])
      create unique_index(:oauth_tokens, [:value])
      create index(:oauth_tokens, [:type])
      create index(:oauth_tokens, [:sub])
    end
  end

  defp sqlite? do
    repo().__adapter__() == Ecto.Adapters.SQLite3
  end
end
