defmodule Micelio.Accounts.OAuthIdentity do
  use Micelio.Schema

  import Ecto.Changeset

  @providers [:github, :gitlab]

  schema "oauth_identities" do
    field :provider, Ecto.Enum, values: @providers
    field :provider_user_id, :string
    field :access_token_encrypted, Micelio.Encrypted.Binary

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of supported OAuth providers.
  """
  def providers, do: @providers

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_user_id, :user_id, :access_token_encrypted])
    |> validate_required([:provider, :provider_user_id, :user_id])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint(:provider_user_id,
      name: :oauth_identities_provider_provider_user_id_index
    )
  end
end
