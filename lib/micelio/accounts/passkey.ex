defmodule Micelio.Accounts.Passkey do
  use Micelio.Schema

  import Ecto.Changeset

  schema "passkeys" do
    field(:credential_id, :binary)
    field(:public_key, :binary)
    field(:sign_count, :integer, default: 0)
    field(:name, :string)
    field(:last_used_at, :utc_datetime)

    belongs_to(:user, Micelio.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:user_id, :credential_id, :public_key, :sign_count, :name, :last_used_at])
    |> validate_required([:user_id, :credential_id, :public_key, :name])
    |> validate_length(:name, min: 2, max: 64)
    |> unique_constraint(:credential_id)
  end

  def usage_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:sign_count, :last_used_at])
    |> validate_required([:sign_count])
  end
end
