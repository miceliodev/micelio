defmodule Micelio.Accounts.OrganizationMembership do
  use Micelio.Schema

  import Ecto.Changeset

  @roles [:admin, :member]

  schema "organization_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :user, Micelio.Accounts.User
    belongs_to :organization, Micelio.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the list of valid membership roles."
  def roles, do: @roles

  @doc """
  Changeset for creating or updating an organization membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :organization_id])
    |> validate_required([:role, :user_id, :organization_id])
    |> validate_inclusion(:role, @roles)
    |> assoc_constraint(:user)
    |> assoc_constraint(:organization)
    |> unique_constraint([:user_id, :organization_id],
      name: :organization_memberships_user_id_organization_id_index
    )
  end
end
