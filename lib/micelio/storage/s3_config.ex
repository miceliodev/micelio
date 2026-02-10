defmodule Micelio.Storage.S3Config do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers [
    :aws_s3,
    :cloudflare_r2,
    :minio,
    :digitalocean_spaces,
    :backblaze_b2,
    :wasabi,
    :custom
  ]
  @region_required_providers [:aws_s3, :digitalocean_spaces, :wasabi]
  @endpoint_required_providers [
    :cloudflare_r2,
    :minio,
    :digitalocean_spaces,
    :backblaze_b2,
    :wasabi,
    :custom
  ]
  @bucket_name_regex ~r/^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$/

  schema "s3_configs" do
    field :provider, Ecto.Enum, values: @providers
    field :bucket_name, :string
    field :region, :string
    field :endpoint_url, :string
    field :access_key_id, Micelio.Encrypted.Binary, redact: true
    field :secret_access_key, Micelio.Encrypted.Binary, redact: true
    field :path_prefix, :string
    field :validated_at, :utc_datetime
    field :last_error, :string

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def user_changeset(config, attrs) do
    config
    |> cast(attrs, [
      :user_id,
      :provider,
      :bucket_name,
      :region,
      :endpoint_url,
      :access_key_id,
      :secret_access_key,
      :path_prefix
    ])
    |> validate_required([
      :user_id,
      :provider,
      :bucket_name,
      :access_key_id,
      :secret_access_key
    ])
    |> validate_bucket_name()
    |> validate_region_requirement()
    |> validate_endpoint_requirement()
    |> unique_constraint(:user_id)
    |> assoc_constraint(:user)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :user_id,
      :provider,
      :bucket_name,
      :region,
      :endpoint_url,
      :access_key_id,
      :secret_access_key,
      :path_prefix,
      :validated_at,
      :last_error
    ])
    |> validate_required([
      :user_id,
      :provider,
      :bucket_name,
      :access_key_id,
      :secret_access_key
    ])
    |> validate_bucket_name()
    |> validate_region_requirement()
    |> validate_endpoint_requirement()
    |> unique_constraint(:user_id)
    |> assoc_constraint(:user)
  end

  defp validate_region_requirement(changeset) do
    case get_field(changeset, :provider) do
      provider when provider in @region_required_providers ->
        validate_required(changeset, [:region])

      _ ->
        changeset
    end
  end

  defp validate_endpoint_requirement(changeset) do
    case get_field(changeset, :provider) do
      provider when provider in @endpoint_required_providers ->
        validate_required(changeset, [:endpoint_url])

      _ ->
        changeset
    end
  end

  defp validate_bucket_name(changeset) do
    changeset
    |> validate_length(:bucket_name, min: 3, max: 63)
    |> validate_format(:bucket_name, @bucket_name_regex,
      message: "must be 3-63 chars, lowercase letters, numbers, and hyphens only"
    )
  end
end
