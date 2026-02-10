defmodule Micelio.AITokens.TokenEarning do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reason_values [:prompt_request_accepted, :prompt_suggestion_submitted]

  schema "ai_token_earnings" do
    field :amount, :integer
    field :reason, Ecto.Enum, values: @reason_values

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User
    belongs_to :prompt_request, Micelio.PromptRequests.PromptRequest
    belongs_to :prompt_suggestion, Micelio.PromptRequests.PromptSuggestion

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
      :prompt_request_id,
      :prompt_suggestion_id
    ])
    |> validate_required([:amount, :reason, :repository_id, :user_id, :prompt_request_id])
    |> validate_number(:amount, greater_than: 0)
    |> maybe_require_prompt_suggestion()
    |> assoc_constraint(:repository)
    |> assoc_constraint(:user)
    |> assoc_constraint(:prompt_request)
    |> assoc_constraint(:prompt_suggestion)
    |> unique_constraint(:prompt_request_id,
      name: :ai_token_earnings_prompt_request_id_user_id_reason_index
    )
  end

  defp maybe_require_prompt_suggestion(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :reason) do
      :prompt_suggestion_submitted -> validate_required(changeset, [:prompt_suggestion_id])
      _ -> changeset
    end
  end
end
