defmodule Micelio.AITokens.TokenContribution do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_token_contributions" do
    field :amount, :integer

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for AI token contributions.
  """
  def changeset(contribution, attrs) do
    contribution
    |> cast(attrs, [:amount, :repository_id, :user_id])
    |> validate_required([:amount, :repository_id, :user_id])
    |> validate_number(:amount, greater_than: 0)
    |> assoc_constraint(:repository)
    |> assoc_constraint(:user)
  end
end
