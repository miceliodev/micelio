defmodule Micelio.Repo.Migrations.CreateDeviceClients do
  use Ecto.Migration

  def change do
    create table(:device_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, :string, null: false
      add :client_secret, :string, null: false
      add :name, :string, null: false
      add :redirect_uris, {:array, :string}, default: [], null: false
      add :grant_types, {:array, :string}, default: [], null: false
      add :access_token_ttl, :integer, null: false
      add :authorization_code_ttl, :integer, null: false
      add :refresh_token_ttl, :integer, null: false
      add :id_token_ttl, :integer, null: false
      add :pkce, :boolean, default: false, null: false
      add :public_refresh_token, :boolean, default: true, null: false
      add :public_revoke, :boolean, default: true, null: false
      add :confidential, :boolean, default: true, null: false
      add :token_endpoint_auth_methods, {:array, :string}, default: [], null: false
      add :token_endpoint_jwt_auth_alg, :string
      add :jwt_public_key, :text
      add :private_key, :text
      add :enforce_dpop, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_clients, [:client_id])
  end
end
