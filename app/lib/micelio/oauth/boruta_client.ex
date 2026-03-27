defmodule Micelio.OAuth.BorutaClient do
  @moduledoc """
  Minimal Boruta client schema mapped to the custom `clients` table used by tokens.
  """

  use Ecto.Schema

  import Ecto.Changeset

  # Note: autogenerate: false because Boruta manages client IDs
  @primary_key {:id, UUIDv7.Type, autogenerate: false}
  @foreign_key_type UUIDv7.Type

  schema "clients" do
    field :secret, :string
    field :name, :string
    field :access_token_ttl, :integer
    field :authorization_code_ttl, :integer
    field :refresh_token_ttl, :integer
    field :id_token_ttl, :integer
    field :redirect_uris, {:array, :string}, default: []
    field :scopes, {:array, :string}, default: []
    field :authorize_scope, :boolean, default: false
    field :supported_grant_types, {:array, :string}, default: []
    field :pkce, :boolean, default: false
    field :public, :boolean, default: false
    field :confidential, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [
      :id,
      :secret,
      :name,
      :access_token_ttl,
      :authorization_code_ttl,
      :refresh_token_ttl,
      :id_token_ttl,
      :redirect_uris,
      :scopes,
      :authorize_scope,
      :supported_grant_types,
      :pkce,
      :public,
      :confidential
    ])
    |> validate_required([
      :id,
      :secret,
      :name,
      :access_token_ttl,
      :authorization_code_ttl,
      :refresh_token_ttl,
      :id_token_ttl
    ])
    |> unique_constraint(:id, name: :clients_pkey)
  end
end
