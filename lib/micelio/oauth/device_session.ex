defmodule Micelio.OAuth.DeviceSession do
  use Micelio.Schema

  import Ecto.Changeset

  alias Micelio.Accounts.User

  schema "device_sessions" do
    field :client_id, :string
    field :client_name, :string
    field :device_name, :string
    field :refresh_token, :string
    field :access_token, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a device session.
  """
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :user_id,
      :client_id,
      :client_name,
      :device_name,
      :refresh_token,
      :access_token,
      :last_used_at
    ])
    |> validate_required([:user_id, :client_id, :client_name, :refresh_token])
    |> assoc_constraint(:user)
  end

  @doc """
  Changeset for revoking a device session.
  """
  def revoke_changeset(session, attrs) do
    session
    |> cast(attrs, [:revoked_at])
    |> validate_required([:revoked_at])
  end
end
