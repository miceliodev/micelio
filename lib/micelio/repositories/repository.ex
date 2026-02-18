defmodule Micelio.Repositories.Repository do
  use Micelio.Schema

  import Ecto.Changeset

  schema "repositories" do
    field :handle, :string
    field :name, :string
    field :description, :string
    field :url, :string
    field :visibility, :string, default: "private"
    field :forge_provider, :string
    field :forge_host, :string
    field :forge_owner, :string
    field :forge_repo, :string
    field :forge_external_id, :string
    field :forge_default_branch, :string
    field :mirror_status, :string, default: "pending"
    field :mirror_last_synced_at, :utc_datetime
    field :star_count, :integer, virtual: true
    field :starred, :boolean, virtual: true

    belongs_to :forked_from, Micelio.Repositories.Repository
    belongs_to :organization, Micelio.Accounts.Organization
    has_many :forks, Micelio.Repositories.Repository, foreign_key: :forked_from_id
    has_many :stars, Micelio.Repositories.RepositoryStar
    has_many :access_tokens, Micelio.Repositories.RepositoryAccessToken
    has_many :webhooks, Micelio.Webhooks.Webhook
    has_many :plans, Micelio.Plans.Plan
    has_many :token_contributions, Micelio.AITokens.TokenContribution
    has_one :token_pool, Micelio.AITokens.TokenPool

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a repository.
  """
  def changeset(repository, attrs, _opts \\ []) do
    repository
    |> cast(attrs, [
      :handle,
      :name,
      :description,
      :url,
      :visibility,
      :forge_provider,
      :forge_host,
      :forge_owner,
      :forge_repo,
      :forge_external_id,
      :forge_default_branch,
      :mirror_status,
      :mirror_last_synced_at
    ])
    |> maybe_put_organization_id(attrs)
    |> validate_required([:handle, :name, :organization_id, :visibility])
    |> validate_handle()
    |> validate_inclusion(:visibility, ["public", "private"])
    |> validate_inclusion(:mirror_status, ["pending", "syncing", "ready", "error"])
    |> normalize_forge_fields()
    |> validate_forge_fields()
    |> normalize_url_change()
    |> validate_url()
    |> unique_constraint(:handle,
      name: :repositories_organization_handle_index,
      message: "has already been taken for this organization"
    )
    |> unique_constraint(:forge_repo, name: :repositories_forge_host_owner_repo_index)
    |> assoc_constraint(:organization)
  end

  @doc """
  Changeset for updating repository settings.
  """
  def settings_changeset(repository, attrs, _opts \\ []) do
    repository
    |> cast(attrs, [:name, :description, :visibility])
    |> validate_required([:name, :visibility])
    |> validate_inclusion(:visibility, ["public", "private"])
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:handle, ~r/^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,99}$/i,
      message:
        "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen"
    )
    |> validate_length(:handle, min: 1, max: 100)
  end

  defp maybe_put_organization_id(changeset, attrs) do
    org_id = Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id")

    if is_nil(org_id) do
      changeset
    else
      put_change(changeset, :organization_id, org_id)
    end
  end

  defp normalize_url_change(changeset) do
    update_change(changeset, :url, fn url ->
      cond do
        is_nil(url) ->
          nil

        is_binary(url) ->
          url = String.trim(url)
          if url != "", do: url

        true ->
          url
      end
    end)
  end

  defp normalize_forge_fields(changeset) do
    changeset
    |> update_change(:forge_provider, &normalize_forge_value/1)
    |> update_change(:forge_host, &normalize_forge_value/1)
    |> update_change(:forge_owner, &normalize_forge_value/1)
    |> update_change(:forge_repo, &normalize_forge_value/1)
    |> update_change(:forge_external_id, &normalize_forge_value/1)
    |> update_change(:forge_default_branch, &normalize_forge_value/1)
  end

  defp normalize_forge_value(nil), do: nil

  defp normalize_forge_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_forge_value(value), do: value

  defp validate_forge_fields(changeset) do
    host = get_field(changeset, :forge_host)
    owner = get_field(changeset, :forge_owner)
    repo = get_field(changeset, :forge_repo)
    provider = get_field(changeset, :forge_provider)

    if Enum.any?([host, owner, repo, provider], &(!is_nil(&1) and &1 != "")) do
      changeset
      |> validate_required([:forge_host, :forge_owner, :forge_repo, :forge_provider])
      |> validate_inclusion(:forge_provider, ["github", "gitlab"])
      |> validate_length(:forge_host, max: 120)
      |> validate_length(:forge_owner, max: 255)
      |> validate_length(:forge_repo, max: 255)
      |> validate_length(:forge_external_id, max: 255)
      |> validate_length(:forge_default_branch, max: 255)
    else
      changeset
    end
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case normalize_url(url) do
        :empty ->
          []

        {:ok, _} ->
          []

        :error ->
          [url: "must be a valid http(s) URL"]
      end
    end)
  end

  defp normalize_url(nil), do: :empty
  defp normalize_url(""), do: :empty

  defp normalize_url(url) when is_binary(url) do
    url = String.trim(url)
    if url == "", do: :empty, else: parse_url(url)
  end

  defp parse_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      {:ok, url}
    else
      :error
    end
  end
end
