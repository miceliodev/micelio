defmodule Micelio.GRPC.Organizations.V1.OrganizationService.Server do
  use GRPC.Server, service: Micelio.GRPC.Organizations.V1.OrganizationService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.Accounts.Organization

  alias Micelio.GRPC.Organizations.V1.{
    GetOrganizationRequest,
    ListOrganizationsRequest,
    ListOrganizationsResponse,
    OrganizationResponse
  }

  alias Micelio.OAuth.AccessTokens

  def list_organizations(%ListOrganizationsRequest{} = request, stream) do
    with {:ok, user} <- fetch_user(request.user_id, stream) do
      organizations = Accounts.list_organizations_for_user(user)

      %ListOrganizationsResponse{
        organizations: Enum.map(organizations, &organization_to_proto/1)
      }
    end
  end

  def get_organization(%GetOrganizationRequest{} = request, stream) do
    with :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      %OrganizationResponse{organization: organization_to_proto(organization)}
    else
      false -> {:error, forbidden_status("You do not have access to this organization.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  defp organization_to_proto(%Organization{} = organization) do
    %Micelio.GRPC.Organizations.V1.Organization{
      id: organization.id,
      handle: organization.account.handle,
      name: organization.name || organization.account.handle,
      description: "",
      inserted_at: format_timestamp(organization.inserted_at),
      updated_at: format_timestamp(organization.updated_at)
    }
  end

  defp fetch_user(user_id, stream) do
    if require_auth_token?(stream) do
      fetch_user_from_token(user_id, stream)
    else
      case empty_to_nil(user_id) do
        nil -> fetch_user_from_token(user_id, stream)
        value -> fetch_user_by_id(value)
      end
    end
  end

  defp fetch_user_by_id(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, unauthenticated_status("User not found.")}
      user -> {:ok, user}
    end
  end

  defp fetch_user_from_token(user_id, stream) do
    with {:ok, token} <- fetch_bearer_token(stream),
         %Boruta.Oauth.Token{} = access_token <- AccessTokens.get_by(value: token),
         user when not is_nil(user) <- Accounts.get_user(access_token.sub) do
      case empty_to_nil(user_id) do
        nil -> {:ok, user}
        value when value == user.id -> {:ok, user}
        _ -> {:error, unauthenticated_status("User does not match access token.")}
      end
    else
      _ -> {:error, unauthenticated_status("User is required.")}
    end
  end

  defp fetch_bearer_token(stream) do
    case Map.get(stream.http_request_headers, "authorization") do
      "Bearer " <> token -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp require_auth_token? do
    config = Application.get_env(:micelio, Micelio.GRPC, [])
    Keyword.get(config, :require_auth_token, false)
  end

  defp require_auth_token?(stream) when is_map(stream) do
    headers = Map.get(stream, :http_request_headers) || %{}

    case Map.get(headers, "x-micelio-require-auth") do
      "true" -> true
      "false" -> false
      _ -> require_auth_token?()
    end
  end

  defp require_auth_token?(_stream), do: require_auth_token?()

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp format_timestamp(%NaiveDateTime{} = timestamp) do
    NaiveDateTime.to_iso8601(timestamp)
  end

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
