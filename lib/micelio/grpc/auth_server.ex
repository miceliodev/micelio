defmodule Micelio.GRPC.Auth.V1.DeviceAuthService.Server do
  use GRPC.Server, service: Micelio.GRPC.Auth.V1.DeviceAuthService.Service

  alias GRPC.RPCError
  alias GRPC.Status

  alias Micelio.GRPC.Auth.V1.{
    DeviceAuthorizationRequest,
    DeviceAuthorizationResponse,
    DeviceClientRegistrationRequest,
    DeviceClientRegistrationResponse,
    DeviceTokenRequest,
    DeviceTokenResponse
  }

  alias Micelio.OAuth
  alias Micelio.OAuth.DeviceClient

  def register_device(%DeviceClientRegistrationRequest{} = request, _stream) do
    attrs =
      if present?(request.name) do
        %{"name" => request.name}
      else
        %{}
      end

    case OAuth.register_device_client(attrs) do
      {:ok, client} ->
        %DeviceClientRegistrationResponse{
          client_id: client.client_id,
          client_secret: client.client_secret
        }

      {:error, _changeset} ->
        {:error, invalid_status("invalid_client")}
    end
  end

  def start_device_authorization(%DeviceAuthorizationRequest{} = request, _stream) do
    with :ok <- require_field(request.client_id, "client_id"),
         %DeviceClient{} = client <- OAuth.get_device_client(request.client_id),
         :ok <- validate_client_secret(client, request.client_secret),
         {:ok, grant} <- OAuth.create_device_grant(client, device_grant_attrs(request)) do
      verification_uri = verification_uri()

      %DeviceAuthorizationResponse{
        device_code: grant.device_code,
        user_code: grant.user_code,
        verification_uri: verification_uri,
        verification_uri_complete:
          verification_uri <> "?" <> URI.encode_query(%{user_code: grant.user_code}),
        expires_in: DateTime.diff(grant.expires_at, DateTime.utc_now(), :second),
        interval: grant.interval
      }
    else
      nil -> {:error, invalid_status("invalid_client")}
      {:error, :invalid_client} -> {:error, unauthenticated_status("invalid_client")}
      {:error, _reason} -> {:error, invalid_status("invalid_request")}
    end
  end

  def exchange_device_code(%DeviceTokenRequest{} = request, _stream) do
    with :ok <- require_field(request.client_id, "client_id"),
         :ok <- require_field(request.device_code, "device_code"),
         %DeviceClient{} = client <- OAuth.get_device_client(request.client_id),
         :ok <- validate_client_secret(client, request.client_secret),
         {:ok, token, _session} <-
           OAuth.exchange_device_code(client.client_id, request.device_code) do
      %DeviceTokenResponse{
        token_type: "Bearer",
        access_token: Map.get(token, :value) || Map.get(token, :access_token) || "",
        refresh_token: Map.get(token, :refresh_token) || "",
        expires_in: Map.get(token, :expires_in) || client.access_token_ttl || 3600
      }
    else
      nil -> {:error, invalid_status("invalid_client")}
      {:error, :invalid_client} -> {:error, unauthenticated_status("invalid_client")}
      {:error, :authorization_pending} -> {:error, failed_precondition("authorization_pending")}
      {:error, :slow_down} -> {:error, failed_precondition("slow_down")}
      {:error, :expired_token} -> {:error, failed_precondition("expired_token")}
      {:error, :invalid_grant} -> {:error, invalid_status("invalid_grant")}
      {:error, _reason} -> {:error, invalid_status("invalid_request")}
    end
  end

  defp device_grant_attrs(request) do
    attrs = %{
      "device_name" => present_or_nil(request.device_name),
      "scope" => present_or_nil(request.scope)
    }

    Enum.reject(attrs, fn {_key, value} -> is_nil(value) end) |> Map.new()
  end

  defp verification_uri do
    MicelioWeb.Endpoint.url() <> "/device/auth"
  end

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name}_required")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name), do: {:error, invalid_status("#{field_name}_required")}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp present_or_nil(value) do
    if present?(value), do: value
  end

  defp validate_client_secret(%DeviceClient{confidential: false}, _secret), do: :ok

  defp validate_client_secret(%DeviceClient{client_secret: secret}, provided)
       when is_binary(provided) and byte_size(provided) == byte_size(secret) do
    if Plug.Crypto.secure_compare(provided, secret), do: :ok, else: {:error, :invalid_client}
  end

  defp validate_client_secret(_client, _provided), do: {:error, :invalid_client}

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)
  defp failed_precondition(message), do: rpc_error(Status.failed_precondition(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
