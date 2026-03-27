defmodule Micelio.Plans.ACPEnvelope do
  use Micelio.Schema

  import Ecto.Changeset

  schema "plan_acp_envelopes" do
    field :direction, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    field :sequence, :integer

    belongs_to :plan, Micelio.Plans.Plan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(envelope, attrs) do
    envelope
    |> cast(attrs, [:plan_id, :direction, :event_type, :payload, :sequence])
    |> validate_required([:plan_id, :direction, :event_type, :payload, :sequence])
    |> validate_length(:direction, max: 32)
    |> validate_length(:event_type, max: 120)
    |> validate_number(:sequence, greater_than: 0)
    |> assoc_constraint(:plan)
  end
end
