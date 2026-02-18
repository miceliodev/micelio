defmodule Micelio.Plans.PlanSuggestion do
  use Micelio.Schema

  import Ecto.Changeset

  schema "plan_suggestions" do
    field :suggestion, :string

    belongs_to :plan, Micelio.Plans.Plan
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan_suggestion, attrs) do
    plan_suggestion
    |> cast(attrs, [:suggestion])
    |> update_change(:suggestion, &normalize_text/1)
    |> validate_required([:suggestion])
    |> validate_length(:suggestion, max: 500)
  end

  defp normalize_text(nil), do: nil
  defp normalize_text(value) when is_binary(value), do: String.trim(value)
end
