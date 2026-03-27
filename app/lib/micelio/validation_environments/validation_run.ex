defmodule Micelio.ValidationEnvironments.ValidationRun do
  use Micelio.Schema

  import Ecto.Changeset

  @statuses [:pending, :running, :passed, :failed]

  schema "validation_runs" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :provider, :string
    field :instance_ref, :map
    field :check_results, :map, default: %{}
    field :metrics, :map, default: %{}
    field :resource_usage, :map, default: %{}
    field :coverage_delta, :float
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :plan, Micelio.Plans.Plan

    timestamps(type: :utc_datetime)
  end

  def changeset(validation_run, attrs) do
    validation_run
    |> cast(attrs, [
      :status,
      :provider,
      :instance_ref,
      :check_results,
      :metrics,
      :resource_usage,
      :coverage_delta,
      :started_at,
      :completed_at,
      :plan_id
    ])
    |> validate_required([:status, :plan_id])
  end
end
