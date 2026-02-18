defmodule Micelio.AITokens.TokenEarning do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reason_values [:plan_accepted, :plan_suggestion_submitted]

  schema "ai_token_earnings" do
    field :amount, :integer
    field :reason, Ecto.Enum, values: @reason_values

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User
    belongs_to :plan, Micelio.Plans.Plan
    belongs_to :plan_suggestion, Micelio.Plans.PlanSuggestion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for AI token earnings.
  """
  def changeset(earning, attrs) do
    earning
    |> cast(attrs, [
      :amount,
      :reason,
      :repository_id,
      :user_id,
      :plan_id,
      :plan_suggestion_id
    ])
    |> validate_required([:amount, :reason, :repository_id, :user_id, :plan_id])
    |> validate_number(:amount, greater_than: 0)
    |> maybe_require_prompt_suggestion()
    |> assoc_constraint(:repository)
    |> assoc_constraint(:user)
    |> assoc_constraint(:plan)
    |> assoc_constraint(:plan_suggestion)
    |> unique_constraint(:plan_id,
      name: :ai_token_earnings_plan_id_user_id_reason_index
    )
  end

  defp maybe_require_prompt_suggestion(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :reason) do
      :plan_suggestion_submitted -> validate_required(changeset, [:plan_suggestion_id])
      _ -> changeset
    end
  end
end
