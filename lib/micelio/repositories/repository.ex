defmodule Micelio.Repositories.Repository do
  use Micelio.Schema

  import Ecto.Changeset

  schema "repositories" do
    field :handle, :string
    field :name, :string
    field :description, :string
    field :url, :string
    field :visibility, :string, default: "private"
    field :star_count, :integer, virtual: true
    field :starred, :boolean, virtual: true

    belongs_to :forked_from, Micelio.Repositories.Repository
    belongs_to :organization, Micelio.Accounts.Organization
    has_many :forks, Micelio.Repositories.Repository, foreign_key: :forked_from_id
    has_many :stars, Micelio.Repositories.RepositoryStar
    has_many :access_tokens, Micelio.Repositories.RepositoryAccessToken
    has_many :webhooks, Micelio.Webhooks.Webhook
    has_many :prompt_requests, Micelio.PromptRequests.PromptRequest
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
      :visibility
    ])
    |> maybe_put_organization_id(attrs)
    |> validate_required([:handle, :name, :organization_id, :visibility])
    |> validate_handle()
    |> validate_inclusion(:visibility, ["public", "private"])
    |> normalize_url_change()
    |> validate_url()
    |> unique_constraint(:handle,
      name: :repositories_organization_handle_index,
      message: "has already been taken for this organization"
    )
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
