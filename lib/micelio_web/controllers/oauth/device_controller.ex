defmodule MicelioWeb.Oauth.DeviceController do
  use MicelioWeb, :controller

  alias Micelio.OAuth
  alias Micelio.OAuth.DeviceClient
  alias Micelio.OAuth.DeviceGrant

  def create(conn, %{"device_code" => device_code}) do
    with %DeviceGrant{} = grant <- OAuth.get_device_grant_by_device_code(device_code),
         {:ok, token, _session} <- OAuth.exchange_device_code(grant.client_id, device_code) do
      client = OAuth.get_device_client(grant.client_id)

      json(conn, %{
        token_type: "Bearer",
        access_token: Map.get(token, :value) || Map.get(token, :access_token) || "",
        refresh_token: Map.get(token, :refresh_token),
        expires_in: token_expires_in(token, client)
      })
    else
      nil ->
        error_response(conn, "invalid_grant", "Device code is invalid.")

      {:error, :authorization_pending} ->
        error_response(conn, "authorization_pending", "Device authorization pending.")

      {:error, :slow_down} ->
        error_response(conn, "slow_down", "Slow down polling.")

      {:error, :expired_token} ->
        error_response(conn, "expired_token", "Device code expired.")

      {:error, :invalid_grant} ->
        error_response(conn, "invalid_grant", "Device code is invalid.")

      {:error, _reason} ->
        error_response(conn, "invalid_request", "Invalid request.")
    end
  end

  def create(conn, params) do
    name = Map.get(params, "device_name")
    attrs = if is_binary(name), do: %{"name" => name}, else: %{}

    with {:ok, client} <- fetch_client(params, attrs),
         {:ok, grant} <- OAuth.create_device_grant(client, device_grant_attrs(params)) do
      verification_uri = MicelioWeb.Endpoint.url() <> "/device/auth"

      json(conn, %{
        device_code: grant.device_code,
        user_code: grant.user_code,
        verification_uri: verification_uri,
        verification_uri_complete:
          verification_uri <> "?" <> URI.encode_query(%{user_code: grant.user_code}),
        expires_in: DateTime.diff(grant.expires_at, DateTime.utc_now(), :second),
        interval: grant.interval
      })
    else
      {:error, :invalid_client} ->
        error_response(conn, "invalid_client", "Invalid client credentials.")

      {:error, _reason} ->
        error_response(conn, "invalid_request", "Invalid request.")
    end
  end

  defp device_grant_attrs(params) do
    attrs = %{
      "device_name" => present_or_nil(Map.get(params, "device_name")),
      "scope" => present_or_nil(Map.get(params, "scope"))
    }

    Enum.reject(attrs, fn {_key, value} -> is_nil(value) end) |> Map.new()
  end

  defp fetch_client(%{"client_id" => client_id, "client_secret" => client_secret}, _attrs)
       when is_binary(client_id) and is_binary(client_secret) do
    case OAuth.get_device_client(client_id) do
      %DeviceClient{client_secret: stored_secret} = client when stored_secret == client_secret ->
        {:ok, client}

      %DeviceClient{} ->
        {:error, :invalid_client}

      _ ->
        {:error, :invalid_client}
    end
  end

  defp fetch_client(%{"client_id" => client_id}, _attrs) when is_binary(client_id) do
    case OAuth.get_device_client(client_id) do
      %DeviceClient{} = client ->
        {:ok, client}

      _ ->
        {:error, :invalid_client}
    end
  end

  defp fetch_client(_params, attrs) do
    OAuth.register_device_client(attrs)
  end

  defp present_or_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp present_or_nil(_value), do: nil

  defp token_expires_in(token, {:ok, client}),
    do: Map.get(token, :expires_in) || client.access_token_ttl || 3600

  defp token_expires_in(token, _client), do: Map.get(token, :expires_in) || 3600

  defp error_response(conn, code, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: code, message: message})
  end
end
