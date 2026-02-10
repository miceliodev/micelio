defmodule Micelio.OAuth.Clients do
  @moduledoc """
  OAuth clients adapter for Boruta that loads CLI clients from the database.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Micelio.OAuth.DeviceClient
  alias Micelio.Repo

  @impl Boruta.Oauth.Clients
  def get_client(client_id) do
    case Repo.get_by(DeviceClient, client_id: client_id) do
      nil -> nil
      client -> to_oauth_client(client)
    end
  end

  @impl Boruta.Oauth.Clients
  def public! do
    nil
  end

  @impl Boruta.Oauth.Clients
  def authorized_scopes(_client), do: []

  @impl Boruta.Oauth.Clients
  def get_client_by_did(_did) do
    nil
  end

  @impl Boruta.Openid.Clients
  def create_client(registration_params) do
    with {:ok, device_client} <- Micelio.OAuth.register_dynamic_client(registration_params) do
      {:ok, to_oauth_client(device_client)}
    end
  end

  @impl Boruta.Oauth.Clients
  def list_clients_jwk, do: []

  @impl Boruta.Openid.Clients
  def refresh_jwk_from_jwks_uri(_client_id) do
    {:error, "JWK refresh from JWKS URI not supported"}
  end

  defp to_oauth_client(%DeviceClient{} = client) do
    %Boruta.Oauth.Client{
      id: client.client_id,
      secret: client.client_secret,
      name: client.name,
      access_token_ttl: client.access_token_ttl,
      authorization_code_ttl: client.authorization_code_ttl,
      refresh_token_ttl: client.refresh_token_ttl,
      id_token_ttl: client.id_token_ttl,
      id_token_signature_alg: client.token_endpoint_jwt_auth_alg,
      userinfo_signed_response_alg: client.token_endpoint_jwt_auth_alg,
      redirect_uris: client.redirect_uris,
      authorize_scope: false,
      supported_grant_types: client.grant_types,
      pkce: client.pkce,
      public_refresh_token: client.public_refresh_token,
      public_revoke: client.public_revoke,
      confidential: client.confidential,
      token_endpoint_auth_methods: client.token_endpoint_auth_methods,
      token_endpoint_jwt_auth_alg: client.token_endpoint_jwt_auth_alg,
      jwt_public_key: client.jwt_public_key,
      private_key: client.private_key,
      enforce_dpop: client.enforce_dpop
    }
  end
end
