defmodule Micelio.OAuth do
  @moduledoc """
  OAuth device flow and device client management.
  """

  import Ecto.Query

  alias Boruta.Oauth.ResourceOwner
  alias Ecto.Multi
  alias Micelio.Accounts.User
  alias Micelio.OAuth.{AccessTokens, BorutaClient, DeviceClient, DeviceGrant, DeviceSession}
  alias Micelio.Repo

  @device_code_ttl_minutes 15
  @device_poll_interval 5
  @access_token_ttl 86_400
  @refresh_token_ttl 2_592_000
  @authorization_code_ttl 60
  @id_token_ttl 86_400

  @doc """
  Registers a new device client.
  """
  def register_device_client(attrs \\ %{}) do
    name = Map.get(attrs, "name") || "Micelio CLI"

    # Generate UUIDs for client_id to match Boruta's expectations
    client_id = Ecto.UUID.generate()
    client_secret = generate_token(48)

    defaults = %{
      "client_id" => client_id,
      "client_secret" => client_secret,
      "name" => name,
      "redirect_uris" => [],
      "grant_types" => [
        "urn:ietf:params:oauth:grant-type:device_code",
        "refresh_token"
      ],
      "access_token_ttl" => @access_token_ttl,
      "authorization_code_ttl" => @authorization_code_ttl,
      "refresh_token_ttl" => @refresh_token_ttl,
      "id_token_ttl" => @id_token_ttl,
      "pkce" => false,
      "public_refresh_token" => true,
      "public_revoke" => true,
      "confidential" => true,
      "token_endpoint_auth_methods" => ["client_secret_post"],
      "token_endpoint_jwt_auth_alg" => "HS256",
      "jwt_public_key" => nil,
      "private_key" => nil,
      "enforce_dpop" => false
    }

    boruta_attrs = %{
      id: client_id,
      secret: client_secret,
      name: name,
      access_token_ttl: @access_token_ttl,
      authorization_code_ttl: @authorization_code_ttl,
      refresh_token_ttl: @refresh_token_ttl,
      id_token_ttl: @id_token_ttl,
      redirect_uris: [],
      scopes: [],
      authorize_scope: false,
      supported_grant_types: defaults["grant_types"],
      pkce: defaults["pkce"],
      public: false,
      confidential: defaults["confidential"]
    }

    Multi.new()
    |> Multi.insert(:boruta_client, BorutaClient.changeset(%BorutaClient{}, boruta_attrs))
    |> Multi.insert(
      :device_client,
      DeviceClient.registration_changeset(%DeviceClient{}, defaults)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{device_client: device_client}} -> {:ok, device_client}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Registers a new OAuth client via dynamic registration.
  """
  def register_dynamic_client(attrs \\ %{}) when is_map(attrs) do
    name = Map.get(attrs, :name) || Map.get(attrs, :client_name) || "Micelio Client"
    redirect_uris = Map.get(attrs, :redirect_uris) || []

    grant_types =
      Map.get(attrs, :grant_types) ||
        [
          "urn:ietf:params:oauth:grant-type:device_code",
          "refresh_token"
        ]

    token_endpoint_auth_methods =
      Map.get(attrs, :token_endpoint_auth_methods) || ["client_secret_post"]

    client_id = Ecto.UUID.generate()
    client_secret = generate_token(48)

    boruta_attrs = %{
      id: client_id,
      secret: client_secret,
      name: name,
      access_token_ttl: @access_token_ttl,
      authorization_code_ttl: @authorization_code_ttl,
      refresh_token_ttl: @refresh_token_ttl,
      id_token_ttl: @id_token_ttl,
      redirect_uris: redirect_uris,
      scopes: [],
      authorize_scope: false,
      supported_grant_types: grant_types,
      pkce: false,
      public: false,
      confidential: true
    }

    device_attrs = %{
      client_id: client_id,
      client_secret: client_secret,
      name: name,
      redirect_uris: redirect_uris,
      grant_types: grant_types,
      access_token_ttl: @access_token_ttl,
      authorization_code_ttl: @authorization_code_ttl,
      refresh_token_ttl: @refresh_token_ttl,
      id_token_ttl: @id_token_ttl,
      pkce: false,
      public_refresh_token: true,
      public_revoke: true,
      confidential: true,
      token_endpoint_auth_methods: token_endpoint_auth_methods,
      token_endpoint_jwt_auth_alg: Map.get(attrs, :token_endpoint_jwt_auth_alg),
      jwt_public_key: Map.get(attrs, :jwt_public_key),
      private_key: Map.get(attrs, :private_key),
      enforce_dpop: false
    }

    Multi.new()
    |> Multi.insert(:boruta_client, BorutaClient.changeset(%BorutaClient{}, boruta_attrs))
    |> Multi.insert(
      :device_client,
      DeviceClient.registration_changeset(%DeviceClient{}, device_attrs)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{device_client: device_client}} -> {:ok, device_client}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Gets a device client by client_id.
  """
  def get_device_client(client_id) do
    Repo.get_by(DeviceClient, client_id: client_id)
  end

  @doc """
  Creates a device authorization grant.
  """
  def create_device_grant(%DeviceClient{} = client, attrs \\ %{}) do
    device_name = Map.get(attrs, "device_name")
    scope = Map.get(attrs, "scope")

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @device_code_ttl_minutes, :minute)

    grant_attrs = %{
      "device_code" => generate_token(32),
      "user_code" => generate_user_code(),
      "client_id" => client.client_id,
      "scope" => scope,
      "device_name" => device_name,
      "expires_at" => expires_at,
      "interval" => @device_poll_interval
    }

    %DeviceGrant{}
    |> DeviceGrant.create_changeset(grant_attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a device grant by device code.
  """
  def get_device_grant_by_device_code(device_code) do
    Repo.get_by(DeviceGrant, device_code: device_code)
  end

  @doc """
  Gets a device grant by user code.
  """
  def get_device_grant_by_user_code(user_code) do
    normalized_code = normalize_user_code(user_code)

    if is_binary(normalized_code) do
      Repo.get_by(DeviceGrant, user_code: normalized_code)
    end
  end

  @doc """
  Approves a device grant for a user.
  """
  def approve_device_grant(user_code, %User{} = user) do
    case get_device_grant_by_user_code(user_code) do
      nil ->
        {:error, :not_found}

      %DeviceGrant{} = grant ->
        with :ok <- ensure_grant_active(grant) do
          grant
          |> DeviceGrant.approve_changeset(%{
            user_id: user.id,
            approved_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()
        end
    end
  end

  @doc """
  Exchanges a device code for tokens.
  """
  def exchange_device_code(client_id, device_code) do
    with %DeviceGrant{} = grant <- get_device_grant_by_device_code(device_code),
         true <- grant.client_id == client_id,
         :ok <- ensure_grant_active(grant),
         :ok <- ensure_poll_interval(grant),
         :ok <- ensure_grant_approved(grant),
         %User{} = user <- Repo.get(User, grant.user_id),
         {:ok, token} <- create_device_tokens(client_id, user, grant.scope),
         {:ok, _} <- mark_grant_used(grant),
         {:ok, session} <- create_device_session(user, token, grant) do
      {:ok, token, session}
    else
      nil -> {:error, :invalid_grant}
      false -> {:error, :invalid_grant}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists device sessions for a user.
  """
  def list_device_sessions_for_user(%User{} = user) do
    DeviceSession
    |> where([s], s.user_id == ^user.id)
    |> where([s], is_nil(s.revoked_at))
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a device session for a user.
  """
  def get_device_session_for_user(%User{} = user, session_id) do
    Repo.get_by(DeviceSession, id: session_id, user_id: user.id)
  end

  @doc """
  Revokes a device session and its refresh token.
  """
  def revoke_device_session(%DeviceSession{} = session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, session} <-
           session
           |> DeviceSession.revoke_changeset(%{revoked_at: now})
           |> Repo.update() do
      revoke_refresh_token(session.refresh_token)
      {:ok, session}
    end
  end

  defp revoke_refresh_token(nil), do: :ok

  defp revoke_refresh_token(refresh_token) do
    case AccessTokens.get_by(refresh_token: refresh_token) do
      %Boruta.Oauth.Token{} = token -> AccessTokens.revoke_refresh_token(token)
      _ -> :ok
    end
  end

  defp ensure_grant_active(%DeviceGrant{} = grant) do
    cond do
      not is_nil(grant.used_at) -> {:error, :invalid_grant}
      DateTime.after?(DateTime.utc_now(), grant.expires_at) -> {:error, :expired_token}
      true -> :ok
    end
  end

  defp ensure_grant_approved(%DeviceGrant{} = grant) do
    if is_nil(grant.approved_at) or is_nil(grant.user_id) do
      {:error, :authorization_pending}
    else
      :ok
    end
  end

  defp ensure_poll_interval(%DeviceGrant{} = grant) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    last_polled_at = grant.last_polled_at

    _ =
      grant
      |> DeviceGrant.poll_changeset(%{last_polled_at: now})
      |> Repo.update()

    if is_nil(last_polled_at) do
      :ok
    else
      poll_diff = DateTime.diff(now, last_polled_at, :second)

      if poll_diff < grant.interval do
        {:error, :slow_down}
      else
        :ok
      end
    end
  end

  defp create_device_tokens(client_id, %User{} = user, scope) do
    case Micelio.OAuth.Clients.get_client(client_id) do
      %Boruta.Oauth.Client{} = client ->
        params = %{
          client: client,
          scope: scope,
          sub: user.id |> to_string(),
          resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
        }

        AccessTokens.create(params, refresh_token: true)

      nil ->
        {:error, :invalid_client}
    end
  end

  defp mark_grant_used(%DeviceGrant{} = grant) do
    grant
    |> DeviceGrant.used_changeset(%{used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  defp create_device_session(%User{} = user, token, %DeviceGrant{} = grant) do
    client_name =
      case Micelio.OAuth.Clients.get_client(grant.client_id) do
        %Boruta.Oauth.Client{} = client -> client.name
        _ -> "Device client"
      end

    access_token = Map.get(token, :value) || Map.get(token, :access_token)
    refresh_token = Map.get(token, :refresh_token)

    attrs = %{
      user_id: user.id,
      client_id: grant.client_id,
      client_name: client_name,
      device_name: grant.device_name,
      access_token: access_token,
      refresh_token: refresh_token,
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %DeviceSession{}
    |> DeviceSession.create_changeset(attrs)
    |> Repo.insert()
  end

  defp generate_token(bytes) do
    :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)
  end

  defp generate_user_code do
    code =
      :crypto.strong_rand_bytes(6)
      |> Base.encode32(padding: false)
      |> String.replace(~r/[^A-Z0-9]/, "")
      |> String.slice(0, 8)

    String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
  end

  defp normalize_user_code(user_code) when is_binary(user_code) do
    user_code
    |> String.trim()
    |> String.replace("-", "")
    |> String.upcase()
    |> then(fn code ->
      if String.length(code) >= 8 do
        String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
      else
        code
      end
    end)
  end

  defp normalize_user_code(_), do: nil
end
