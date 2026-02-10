defmodule Micelio.AITokens.TaskBudget do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_token_task_budgets" do
    field :amount, :integer, default: 0

    belongs_to :token_pool, Micelio.AITokens.TokenPool
    belongs_to :prompt_request, Micelio.PromptRequests.PromptRequest

    timestamps(type: :utc_datetime)
  end

  def changeset(task_budget, attrs) do
    task_budget
    |> cast(attrs, [:amount])
    |> validate_required([:amount])
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> assoc_constraint(:token_pool)
    |> assoc_constraint(:prompt_request)
    |> unique_constraint(:prompt_request_id)
  end
end
