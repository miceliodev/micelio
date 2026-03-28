defmodule Micelio.Accounts.User do
  use Micelio.Schema

  import Ecto.Changeset

  @supported_locales ~w(en es ko zh_CN zh_TW ja)
  @profile_fields [
    :bio,
    :locale,
    :website_url,
    :twitter_url,
    :github_url,
    :gitlab_url,
    :mastodon_url,
    :linkedin_url
  ]
  @profile_url_fields [
    :website_url,
    :twitter_url,
    :github_url,
    :gitlab_url,
    :mastodon_url,
    :linkedin_url
  ]

  schema "users" do
    field(:email, :string)
    field(:bio, :string)
    field(:locale, :string, default: "en")
    field(:website_url, :string)
    field(:twitter_url, :string)
    field(:github_url, :string)
    field(:gitlab_url, :string)
    field(:mastodon_url, :string)
    field(:linkedin_url, :string)
    field(:totp_secret, :binary)
    field(:totp_enabled_at, :utc_datetime)
    field(:totp_last_used_at, :utc_datetime)

    has_one(:account, Micelio.Accounts.Account)
    has_many(:organization_memberships, Micelio.Accounts.OrganizationMembership)
    has_many(:organizations, through: [:organization_memberships, :organization])
    has_many(:repository_access_tokens, Micelio.Repositories.RepositoryAccessToken)
    has_many(:plans, Micelio.Plans.Plan)
    has_many(:plan_suggestions, Micelio.Plans.PlanSuggestion)
    has_many(:token_contributions, Micelio.AITokens.TokenContribution)
    has_many(:token_earnings, Micelio.AITokens.TokenEarning)
    has_many(:oauth_identities, Micelio.Accounts.OAuthIdentity)
    has_many(:passkeys, Micelio.Accounts.Passkey)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new user.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email()
    |> unique_constraint(:email, name: :users_email_index)
  end

  @doc """
  Changeset for updating public profile details.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, @profile_fields)
    |> update_change(:bio, &trim_optional/1)
    |> validate_length(:bio, max: 160)
    |> validate_inclusion(:locale, @supported_locales)
    |> normalize_url_fields()
    |> validate_url_fields()
  end

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
  end

  defp normalize_url_fields(changeset) do
    Enum.reduce(@profile_url_fields, changeset, fn field, changeset ->
      case get_change(changeset, field) do
        nil ->
          changeset

        value ->
          trimmed = trim_optional(value)

          cond do
            trimmed in [nil, ""] ->
              put_change(changeset, field, nil)

            String.starts_with?(trimmed, ["http://", "https://"]) ->
              put_change(changeset, field, trimmed)

            true ->
              put_change(changeset, field, "https://" <> trimmed)
          end
      end
    end)
  end

  defp validate_url_fields(changeset) do
    changeset =
      Enum.reduce(@profile_url_fields, changeset, fn field, changeset ->
        validate_length(changeset, field, max: 200)
      end)

    Enum.reduce(@profile_url_fields, changeset, fn field, changeset ->
      case get_field(changeset, field) do
        nil ->
          changeset

        value ->
          if valid_url?(value) do
            changeset
          else
            add_error(changeset, field, "must be a valid URL")
          end
      end
    end)
  end

  defp valid_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  end

  defp trim_optional(nil), do: nil
  defp trim_optional(value) when is_binary(value), do: String.trim(value)
end
