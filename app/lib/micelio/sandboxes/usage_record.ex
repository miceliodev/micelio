defmodule Micelio.Sandboxes.UsageRecord do
  use Micelio.Schema

  import Ecto.Changeset

  schema "agentic_usage_records" do
    field :date, :date
    field :active_workspaces, :integer, default: 0
    field :daily_minutes_used, :integer, default: 0

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:user_id, :date, :active_workspaces, :daily_minutes_used])
    |> validate_required([:user_id, :date])
    |> validate_number(:active_workspaces, greater_than_or_equal_to: 0)
    |> validate_number(:daily_minutes_used, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :date])
  end
end
