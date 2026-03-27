defmodule Micelio.OAuth.DeviceClient do
  use Micelio.Schema

  import Ecto.Changeset

  schema "device_clients" do
    field :client_id, :string
    field :client_secret, :string
    field :name, :string
    field :redirect_uris, {:array, :string}, default: []
    field :grant_types, {:array, :string}, default: []
    field :access_token_ttl, :integer
    field :authorization_code_ttl, :integer
    field :refresh_token_ttl, :integer
    field :id_token_ttl, :integer
    field :pkce, :boolean, default: false
    field :public_refresh_token, :boolean, default: true
    field :public_revoke, :boolean, default: true
    field :confidential, :boolean, default: true
    field :token_endpoint_auth_methods, {:array, :string}, default: []
    field :token_endpoint_jwt_auth_alg, :string
    field :jwt_public_key, :string
    field :private_key, :string
    field :enforce_dpop, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for registering a CLI device client.
  """
  def registration_changeset(client, attrs) do
    client
    |> cast(attrs, [
      :client_id,
      :client_secret,
      :name,
      :redirect_uris,
      :grant_types,
      :access_token_ttl,
      :authorization_code_ttl,
      :refresh_token_ttl,
      :id_token_ttl,
      :pkce,
      :public_refresh_token,
      :public_revoke,
      :confidential,
      :token_endpoint_auth_methods,
      :token_endpoint_jwt_auth_alg,
      :jwt_public_key,
      :private_key,
      :enforce_dpop
    ])
    |> validate_required([:client_id, :client_secret, :name])
    |> validate_length(:name, min: 1, max: 120)
    |> unique_constraint(:client_id)
  end
end
