defmodule Micelio.GRPC.Repositories.V1.ProjectService.Server do
  use GRPC.Server, service: Micelio.GRPC.Repositories.V1.ProjectService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Repositories.V1

  alias Micelio.GRPC.Repositories.V1.{
    CreateProjectRequest,
    DeleteProjectRequest,
    GetProjectRequest,
    ListProjectsRequest,
    ListProjectsResponse,
    UpdateProjectRequest
  }

  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository

  def list_projects(%ListProjectsRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle) do
      case fetch_optional_user(request.user_id, stream) do
        {:ok, user} ->
          repositories =
            if Accounts.user_in_organization?(user, organization.id) do
              Repositories.list_repositories_for_organization(organization.id)
            else
              Repositories.list_public_repositories_for_organization(organization.id)
            end

          %ListProjectsResponse{
            repositories: Enum.map(repositories, &repository_to_proto(&1, organization))
          }

        :anonymous ->
          repositories = Repositories.list_public_repositories_for_organization(organization.id)

          %ListProjectsResponse{
            repositories: Enum.map(repositories, &repository_to_proto(&1, organization))
          }

        {:error, status} ->
          {:error, status}
      end
    else
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_project(%GetProjectRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         %Repository{} = repository <-
           Repositories.get_repository_by_handle(organization.id, request.handle),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream) do
      %V1.ProjectResponse{repository: repository_to_proto(repository, organization)}
    else
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
    end
  end

  def create_project(%CreateProjectRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         :ok <- require_field(request.name, "name"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      attrs =
        %{
          handle: request.handle,
          name: request.name,
          description: empty_to_nil(request.description),
          organization_id: organization.id
        }
        |> maybe_put_visibility(request.visibility)

      case Repositories.create_repository(attrs, user: user) do
        {:ok, repository} ->
          %V1.ProjectResponse{repository: repository_to_proto(repository, organization)}

        {:error, changeset} ->
          {:error, invalid_status("Invalid repository: #{format_errors(changeset)}")}
      end
    else
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def update_project(%UpdateProjectRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Repository{} = repository <-
           Repositories.get_repository_by_handle(organization.id, request.handle) do
      attrs =
        %{
          handle: empty_to_nil(request.new_handle) || repository.handle,
          name: empty_to_nil(request.name) || repository.name,
          description: empty_to_nil(request.description)
        }
        |> maybe_put_visibility(request.visibility)

      case Repositories.update_repository(repository, attrs, user: user) do
        {:ok, updated} ->
          %V1.ProjectResponse{repository: repository_to_proto(updated, organization)}

        {:error, changeset} ->
          {:error, invalid_status("Invalid repository: #{format_errors(changeset)}")}
      end
    else
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def delete_project(%DeleteProjectRequest{} = request, stream) do
    with :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Repository{} = repository <-
           Repositories.get_repository_by_handle(organization.id, request.handle),
         {:ok, _} <- Repositories.delete_repository(repository, user: user) do
      %V1.DeleteProjectResponse{success: true}
    else
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  defp repository_to_proto(repository, organization) do
    organization_handle = organization.account.handle

    %V1.Project{
      id: repository.id,
      organization_id: organization.id,
      organization_handle: organization_handle,
      handle: repository.handle,
      name: repository.name,
      description: repository.description || "",
      visibility: repository.visibility,
      inserted_at: format_timestamp(repository.inserted_at),
      updated_at: format_timestamp(repository.updated_at)
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

  defp fetch_optional_user(user_id, stream) do
    if require_auth_token?(stream) do
      fetch_user(user_id, stream)
    else
      case empty_to_nil(user_id) do
        nil -> :anonymous
        value -> fetch_user_by_id(value)
      end
    end
  end

  defp authorize_repository_read(organization, repository, user_id, stream) do
    if repository.visibility == "public" do
      if require_auth_token?(stream) do
        case fetch_user(user_id, stream) do
          {:ok, _user} -> :ok
          {:error, status} -> {:error, status}
        end
      else
        :ok
      end
    else
      with {:ok, user} <- fetch_user(user_id, stream),
           true <- Accounts.user_in_organization?(user, organization.id) do
        :ok
      else
        false -> {:error, forbidden_status("You do not have access to this organization.")}
        {:error, status} -> {:error, status}
      end
    end
  end

  defp maybe_put_visibility(attrs, visibility) do
    case empty_to_nil(visibility) do
      nil -> attrs
      value -> Map.put(attrs, :visibility, value)
    end
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field} #{Enum.join(errors, ", ")}"
    end)
  end

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
