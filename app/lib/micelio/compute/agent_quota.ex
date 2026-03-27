defmodule Micelio.AgentInfra.AgentQuota do
  use Micelio.Schema

  import Ecto.Changeset

  schema "agent_quotas" do
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :cpu_core_seconds_limit, :integer
    field :memory_mb_seconds_limit, :integer
    field :disk_gb_seconds_limit, :integer
    field :billable_units_limit, :integer
    field :cpu_core_seconds_used, :integer, default: 0
    field :memory_mb_seconds_used, :integer, default: 0
    field :disk_gb_seconds_used, :integer, default: 0
    field :billable_units_used, :integer, default: 0
    field :cost_cents_used, :integer, default: 0

    belongs_to :account, Micelio.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(quota, attrs) do
    quota
    |> cast(attrs, [
      :account_id,
      :period_start,
      :period_end,
      :cpu_core_seconds_limit,
      :memory_mb_seconds_limit,
      :disk_gb_seconds_limit,
      :billable_units_limit,
      :cpu_core_seconds_used,
      :memory_mb_seconds_used,
      :disk_gb_seconds_used,
      :billable_units_used,
      :cost_cents_used
    ])
    |> validate_required([
      :account_id,
      :period_start,
      :period_end,
      :cpu_core_seconds_limit,
      :memory_mb_seconds_limit,
      :disk_gb_seconds_limit,
      :billable_units_limit
    ])
    |> assoc_constraint(:account)
  end

  def usage_changeset(%__MODULE__{} = quota, usage) do
    change(quota,
      cpu_core_seconds_used: quota.cpu_core_seconds_used + usage.cpu_core_seconds,
      memory_mb_seconds_used: quota.memory_mb_seconds_used + usage.memory_mb_seconds,
      disk_gb_seconds_used: quota.disk_gb_seconds_used + usage.disk_gb_seconds,
      billable_units_used: quota.billable_units_used + usage.billable_units,
      cost_cents_used: quota.cost_cents_used + usage.cost_cents
    )
  end
end
