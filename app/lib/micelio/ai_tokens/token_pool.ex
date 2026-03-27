defmodule Micelio.AITokens.TokenPool do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_token_pools" do
    field :balance, :integer, default: 0
    field :reserved, :integer, default: 0

    belongs_to :repository, Micelio.Repositories.Repository

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for AI token pools.
  """
  def changeset(token_pool, attrs) do
    token_pool
    |> cast(attrs, [:repository_id, :balance, :reserved])
    |> validate_required([:repository_id, :balance, :reserved])
    |> validate_number(:balance, greater_than_or_equal_to: 0)
    |> validate_number(:reserved, greater_than_or_equal_to: 0)
    |> validate_reserved_not_over_balance()
    |> unique_constraint(:repository_id)
    |> assoc_constraint(:repository)
  end

  defp validate_reserved_not_over_balance(changeset) do
    balance = get_field(changeset, :balance)
    reserved = get_field(changeset, :reserved)

    if is_integer(balance) and is_integer(reserved) and reserved > balance do
      add_error(changeset, :reserved, "cannot exceed balance")
    else
      changeset
    end
  end
end
