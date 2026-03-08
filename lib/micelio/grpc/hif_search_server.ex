defmodule Micelio.GRPC.Hif.V1.SearchService.Server do
  use GRPC.Server, service: Micelio.GRPC.Hif.V1.SearchService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Hif.V1
  alias Micelio.Mic.SearchIndex
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Repositories

  def query_text(%V1.TextQueryRequest{} = request, stream) do
    with :ok <- require_repository_ref(request.repository),
         :ok <- require_field(request.query, "query"),
         {:ok, organization, repository} <- load_repository(request.repository),
         :ok <- authorize_repository_read(organization, repository, request.user_id, stream),
         {:ok, offset} <- resolve_offset(request.offset, request.page_token),
         params = %{
           query: request.query,
           at_revision_hash: normalize_revision_hash(request.at_revision_hash),
           path_prefix: empty_to_nil(request.path_prefix),
           path_glob: empty_to_nil(request.path_glob),
           regex: request.regex,
           case_sensitive: request.case_sensitive,
           limit: normalize_limit(request.limit),
           offset: offset
         },
         {:ok, %{total: total, matches: matches, next_offset: next_offset}} <-
           SearchIndex.query(repository.id, params) do
      %V1.TextQueryResponse{
        total: total,
        matches: Enum.map(matches, &to_query_match/1),
        next_page_token: encode_next_page_token(next_offset)
      }
    else
      {:error, :stale_index} ->
        {:error,
         %RPCError{
           status: Status.failed_precondition(),
           message: "Search index is stale. Retry after index catch-up."
         }}

      {:error, status} ->
        {:error, status}
    end
  end

  defp to_query_match(posting) do
    %V1.TextQueryMatch{
      path: posting.path,
      line: posting.line,
      column: posting.column,
      snippet: posting.snippet,
      session_id: posting.session_id,
      actor_handle: posting.actor_handle,
      revision_hash: Map.get(posting, :revision_hash, <<>>),
      revision_etag:
        case Map.get(posting, :revision_hash) do
          hash when is_binary(hash) and byte_size(hash) == 32 ->
            "revision-#{Base.encode16(hash, case: :lower)}"

          _ ->
            ""
        end
    }
  end

  defp encode_next_page_token(nil), do: <<>>

  defp encode_next_page_token(offset) when is_integer(offset) do
    Jason.encode!(%{"offset" => offset})
  end

  defp resolve_offset(_offset, page_token)
       when is_binary(page_token) and byte_size(page_token) > 0 do
    case Jason.decode(page_token) do
      {:ok, %{"offset" => token_offset}} ->
        {:ok, normalize_offset(token_offset)}

      _ ->
        {:error, invalid_status("page_token is invalid.")}
    end
  end

  defp resolve_offset(offset, _page_token), do: {:ok, normalize_offset(offset)}

  defp normalize_revision_hash(hash) when is_binary(hash) and byte_size(hash) == 32, do: hash
  defp normalize_revision_hash(_hash), do: nil

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 and limit <= 500, do: limit
  defp normalize_limit(_limit), do: 20

  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_offset), do: 0

  defp load_repository(%V1.RepositoryRef{} = repository_ref) do
    with {:ok, organization} <-
           Accounts.get_organization_by_handle(repository_ref.organization_handle),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(
             organization.id,
             repository_ref.repository_handle
           ) do
      {:ok, organization, Repositories.get_repository_with_organization(repository.id)}
    else
      nil -> {:error, not_found_status("Repository not found.")}
      {:error, :not_found} -> {:error, not_found_status("Organization not found.")}
      {:error, status} -> {:error, status}
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

  defp require_repository_ref(%V1.RepositoryRef{} = repository_ref) do
    with :ok <-
           require_field(repository_ref.organization_handle, "repository.organization_handle") do
      require_field(repository_ref.repository_handle, "repository.repository_handle")
    end
  end

  defp require_repository_ref(_), do: {:error, invalid_status("repository is required.")}

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp invalid_status(message) do
    %RPCError{status: Status.invalid_argument(), message: message}
  end

  defp unauthenticated_status(message) do
    %RPCError{status: Status.unauthenticated(), message: message}
  end

  defp forbidden_status(message) do
    %RPCError{status: Status.permission_denied(), message: message}
  end

  defp not_found_status(message) do
    %RPCError{status: Status.not_found(), message: message}
  end
end
