defmodule Micelio.AgentInfra.AgentUsageEvent do
  use Micelio.Schema

  import Ecto.Changeset

  schema "agent_usage_events" do
    field :source, :string
    field :cpu_core_seconds, :integer
    field :memory_mb_seconds, :integer
    field :disk_gb_seconds, :integer
    field :billable_units, :integer
    field :cost_cents, :integer
    field :metadata, :map, default: %{}

    belongs_to :account, Micelio.Accounts.Account

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :account_id,
      :source,
      :cpu_core_seconds,
      :memory_mb_seconds,
      :disk_gb_seconds,
      :billable_units,
      :cost_cents,
      :metadata
    ])
    |> validate_required([
      :account_id,
      :source,
      :cpu_core_seconds,
      :memory_mb_seconds,
      :disk_gb_seconds,
      :billable_units,
      :cost_cents
    ])
    |> assoc_constraint(:account)
  end
end
