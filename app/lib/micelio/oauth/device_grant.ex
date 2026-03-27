defmodule Micelio.OAuth.DeviceGrant do
  use Micelio.Schema

  import Ecto.Changeset

  alias Micelio.Accounts.User

  schema "device_grants" do
    field :device_code, :string
    field :user_code, :string
    field :client_id, :string
    field :scope, :string
    field :device_name, :string
    field :expires_at, :utc_datetime
    field :interval, :integer
    field :last_polled_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a device grant.
  """
  def create_changeset(grant, attrs) do
    grant
    |> cast(attrs, [
      :device_code,
      :user_code,
      :client_id,
      :scope,
      :device_name,
      :expires_at,
      :interval
    ])
    |> validate_required([:device_code, :user_code, :client_id, :expires_at, :interval])
    |> unique_constraint(:device_code)
    |> unique_constraint(:user_code)
  end

  @doc """
  Changeset for approving a device grant.
  """
  def approve_changeset(grant, attrs) do
    grant
    |> cast(attrs, [:user_id, :approved_at])
    |> validate_required([:user_id, :approved_at])
  end

  @doc """
  Changeset for polling updates on a device grant.
  """
  def poll_changeset(grant, attrs) do
    grant
    |> cast(attrs, [:last_polled_at])
  end

  @doc """
  Changeset for marking a device grant as used.
  """
  def used_changeset(grant, attrs) do
    grant
    |> cast(attrs, [:used_at])
  end
end
