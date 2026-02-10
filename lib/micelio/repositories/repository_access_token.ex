defmodule Micelio.Repositories.RepositoryAccessToken do
  use Micelio.Schema

  import Ecto.Changeset

  @allowed_scopes ["read", "write"]

  schema "repository_access_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :token_prefix, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a repository access token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :name,
      :token_hash,
      :token_prefix,
      :scopes,
      :repository_id,
      :user_id,
      :expires_at,
      :last_used_at,
      :revoked_at
    ])
    |> normalize_scopes()
    |> validate_required([:name, :token_hash, :token_prefix, :scopes, :repository_id, :user_id])
    |> validate_length(:name, max: 120)
    |> validate_length(:scopes, min: 1)
    |> validate_scopes()
    |> assoc_constraint(:repository)
    |> assoc_constraint(:user)
    |> unique_constraint(:token_hash)
  end

  @doc """
  Changeset for creating a new repository access token.
  """
  def create_changeset(token, attrs) do
    changeset(token, attrs)
  end

  @doc """
  Changeset for revoking an access token.
  """
  def revoke_changeset(%__MODULE__{} = token) do
    change(token,
      revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  @doc """
  Changeset for updating last usage timestamp.
  """
  def touch_changeset(%__MODULE__{} = token) do
    change(token,
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  @doc """
  Returns the list of allowed scopes.
  """
  def allowed_scopes do
    @allowed_scopes
  end

  @doc """
  Generates a token and returns {token, token_hash}.
  """
  def generate_token do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {token, hash_token(token)}
  end

  @doc """
  Hashes a token value for storage lookup.
  """
  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
  end

  @doc """
  Returns true if the token is active (not expired or revoked).
  """
  def active?(%__MODULE__{} = token) do
    not revoked?(token) and not expired?(token)
  end

  @doc """
  Checks whether the token's scopes allow the requested scope.
  """
  def scope_allows?(%__MODULE__{scopes: scopes}, required_scope) when is_binary(required_scope) do
    required_scope in scopes or (required_scope == "read" and "write" in scopes)
  end

  def scope_allows?(_token, _required_scope), do: false

  defp revoked?(%__MODULE__{revoked_at: nil}), do: false
  defp revoked?(%__MODULE__{revoked_at: %DateTime{}}), do: true
  defp revoked?(_), do: true

  defp expired?(%__MODULE__{expires_at: nil}), do: false

  defp expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}) do
    DateTime.before?(expires_at, DateTime.utc_now())
  end

  defp expired?(_), do: true

  defp normalize_scopes(changeset) do
    update_change(changeset, :scopes, fn scopes ->
      if is_list(scopes) do
        scopes
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()
      else
        scopes
      end
    end)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      cond do
        not is_list(scopes) ->
          [scopes: "must be a list"]

        Enum.any?(scopes, &(!is_binary(&1) or &1 == "")) ->
          [scopes: "must contain only non-empty strings"]

        true ->
          invalid = Enum.reject(scopes, &(&1 in @allowed_scopes))

          if invalid == [] do
            []
          else
            [scopes: "contains unsupported scopes: #{Enum.join(invalid, ", ")}"]
          end
      end
    end)
  end
end
