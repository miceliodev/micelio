defmodule Micelio.Repositories.AccessTokens do
  @moduledoc """
  Repository-scoped access tokens with read/write permissions.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Repo
  alias Micelio.Repositories.Repository
  alias Micelio.Repositories.RepositoryAccessToken

  @token_prefix "mpt_"
  @token_bytes 32
  @token_prefix_length 8

  @doc """
  Creates a new repository access token and returns the plaintext token once.
  """
  def create(%Repository{} = repository, %Accounts.User{} = user, attrs) when is_map(attrs) do
    token = generate_token()
    token_hash = hash_token(token)

    attrs =
      attrs
      |> Map.put(:repository_id, repository.id)
      |> Map.put(:user_id, user.id)
      |> Map.put(:token_hash, token_hash)
      |> Map.put(:token_prefix, String.slice(token, 0, @token_prefix_length))

    %RepositoryAccessToken{}
    |> RepositoryAccessToken.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, token, record}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Lists tokens for a repository (excluding secrets).
  """
  def list_for_repository(repository_id) do
    RepositoryAccessToken
    |> where([t], t.repository_id == ^repository_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Fetches a valid token by plaintext value.
  """
  def get_valid_by_token(token) when is_binary(token) do
    token
    |> get_by_token()
    |> ensure_valid()
  end

  @doc """
  Authenticates a token for a repository and required scopes.
  """
  def authenticate(token, repository_id, required_scopes \\ [])
      when is_binary(token) and is_binary(repository_id) do
    with %RepositoryAccessToken{} = access_token <- get_valid_by_token(token),
         true <- access_token.repository_id == repository_id,
         true <- scopes_cover?(access_token.scopes, required_scopes),
         %Accounts.User{} = user <- Accounts.get_user(access_token.user_id) do
      _ = touch(access_token)
      {:ok, user, access_token}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Revokes a token.
  """
  def revoke(%RepositoryAccessToken{} = access_token) do
    access_token
    |> RepositoryAccessToken.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Updates the last usage timestamp.
  """
  def touch(%RepositoryAccessToken{} = access_token) do
    access_token
    |> RepositoryAccessToken.touch_changeset()
    |> Repo.update()
  end

  defp ensure_valid(nil), do: nil

  defp ensure_valid(%RepositoryAccessToken{} = access_token) do
    if active?(access_token) do
      access_token
    end
  end

  defp active?(%RepositoryAccessToken{} = access_token) do
    not revoked?(access_token) and not expired?(access_token)
  end

  defp revoked?(%RepositoryAccessToken{revoked_at: nil}), do: false
  defp revoked?(%RepositoryAccessToken{}), do: true

  defp expired?(%RepositoryAccessToken{expires_at: nil}), do: false

  defp expired?(%RepositoryAccessToken{expires_at: expires_at}) do
    DateTime.before?(expires_at, DateTime.utc_now())
  end

  defp get_by_token(token) when is_binary(token) do
    Repo.get_by(RepositoryAccessToken, token_hash: hash_token(token))
  end

  defp scopes_cover?(token_scopes, required_scopes) do
    required = normalize_scopes(required_scopes)
    available = normalize_scopes(token_scopes)
    Enum.all?(required, &(&1 in available))
  end

  defp normalize_scopes(scopes) when is_list(scopes) do
    scopes
    |> Enum.flat_map(&expand_scope/1)
    |> Enum.uniq()
  end

  defp normalize_scopes(scope) when is_binary(scope), do: normalize_scopes([scope])
  defp normalize_scopes(_), do: []

  defp expand_scope("write"), do: ["write", "read"]
  defp expand_scope(scope), do: [scope]

  defp generate_token do
    @token_prefix <>
      (:crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false))
  end

  defp hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
  end
end
