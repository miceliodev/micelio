defmodule Micelio.Repo.Migrations.CreateBoruta do
  use Ecto.Migration

  # Custom Boruta migration to avoid table name conflicts
  def change do
    create table(:clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :secret, :string
      add :name, :string, null: false
      add :access_token_ttl, :integer, null: false
      add :authorization_code_ttl, :integer, null: false
      add :refresh_token_ttl, :integer, null: false
      add :id_token_ttl, :integer, null: false
      add :redirect_uris, {:array, :string}, null: false, default: []
      add :scopes, {:array, :string}, null: false, default: []
      add :authorize_scope, :boolean, null: false, default: false
      add :supported_grant_types, {:array, :string}, null: false, default: []
      add :pkce, :boolean, null: false, default: false
      add :public, :boolean, null: false, default: false
      add :confidential, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clients, [:id])

    # Standard Boruta tokens table with custom name to avoid conflicts
    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :value, :string, null: false
      add :revoked_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :redirect_uri, :string
      add :state, :string
      add :scope, :string
      add :sub, :string
      add :client_id, references(:clients, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:oauth_tokens, [:client_id])
    create unique_index(:oauth_tokens, [:value])
    create index(:oauth_tokens, [:type])
    create index(:oauth_tokens, [:sub])
  end
end
