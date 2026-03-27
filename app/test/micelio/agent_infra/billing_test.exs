defmodule Micelio.AgentInfra.BillingTest do
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.AgentInfra
  alias Micelio.AgentInfra.AgentQuota
  alias Micelio.AgentInfra.AgentUsageEvent
  alias Micelio.AgentInfra.Billing
  alias Micelio.AgentInfra.ProvisioningRequest
  alias Micelio.Repo

  defp unique_email(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}@example.com"
  end

  test "reserve_for_plan/3 records usage and updates quota" do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("billing"))
    account = user.account

    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 1024,
      disk_gb: 10,
      ttl_seconds: 60
    }

    {:ok, plan} = AgentInfra.build_plan(attrs)

    opts = [
      limits: %{
        cpu_core_seconds: 10_000,
        memory_mb_seconds: 200_000,
        disk_gb_seconds: 20_000,
        billable_units: 1_000_000
      },
      unit_weights: %{cpu_core_second: 2, memory_mb_second: 1, disk_gb_second: 3},
      unit_price_cents: 2
    ]

    usage = Billing.usage_from_plan(plan, opts)

    assert {:ok, %AgentUsageEvent{} = event} = Billing.reserve_for_plan(account, plan, opts)
    assert event.billable_units == usage.billable_units
    assert event.cost_cents == usage.cost_cents

    {period_start, _period_end} = Billing.quota_period(DateTime.utc_now())
    quota = Repo.get_by!(AgentQuota, account_id: account.id, period_start: period_start)

    assert quota.cpu_core_seconds_used == usage.cpu_core_seconds
    assert quota.memory_mb_seconds_used == usage.memory_mb_seconds
    assert quota.disk_gb_seconds_used == usage.disk_gb_seconds
    assert quota.billable_units_used == usage.billable_units
    assert quota.cost_cents_used == usage.cost_cents
  end

  test "reserve_for_plan/3 enforces quota limits" do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("billing-limit"))
    account = user.account

    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 1024,
      disk_gb: 10,
      ttl_seconds: 60
    }

    {:ok, plan} = AgentInfra.build_plan(attrs)

    opts = [
      limits: %{
        cpu_core_seconds: 100,
        memory_mb_seconds: 100,
        disk_gb_seconds: 100,
        billable_units: 100
      }
    ]

    assert {:error, {:quota_exceeded, exceeded}} = Billing.reserve_for_plan(account, plan, opts)
    assert :cpu_core_seconds in exceeded
  end

  test "quota_status/2 creates a quota record and reports remaining limits" do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("billing-status"))
    account = user.account

    limits = %{
      cpu_core_seconds: 1_000,
      memory_mb_seconds: 2_000,
      disk_gb_seconds: 3_000,
      billable_units: 4_000
    }

    assert {:ok, status} = Billing.quota_status(account, limits: limits)

    assert status.limits.cpu_core_seconds == 1_000
    assert status.limits.memory_mb_seconds == 2_000
    assert status.limits.disk_gb_seconds == 3_000
    assert status.limits.billable_units == 4_000

    assert status.used.cpu_core_seconds == 0
    assert status.used.memory_mb_seconds == 0
    assert status.used.disk_gb_seconds == 0
    assert status.used.billable_units == 0
    assert status.used.cost_cents == 0

    assert status.remaining.cpu_core_seconds == 1_000
    assert status.remaining.memory_mb_seconds == 2_000
    assert status.remaining.disk_gb_seconds == 3_000
    assert status.remaining.billable_units == 4_000
    assert status.remaining.cost_cents == nil
  end

  test "quota_status/2 reflects reserved usage" do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("billing-usage"))
    account = user.account

    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 512,
      disk_gb: 5,
      ttl_seconds: 120
    }

    {:ok, plan} = AgentInfra.build_plan(attrs)

    limits = %{
      cpu_core_seconds: 10_000,
      memory_mb_seconds: 200_000,
      disk_gb_seconds: 50_000,
      billable_units: 1_000_000
    }

    opts = [limits: limits]

    usage = Billing.usage_from_plan(plan, opts)
    assert {:ok, %AgentUsageEvent{}} = Billing.reserve_for_plan(account, plan, opts)

    assert {:ok, status} = Billing.quota_status(account, opts)

    assert status.used.cpu_core_seconds == usage.cpu_core_seconds
    assert status.used.memory_mb_seconds == usage.memory_mb_seconds
    assert status.used.disk_gb_seconds == usage.disk_gb_seconds
    assert status.used.billable_units == usage.billable_units

    assert status.remaining.cpu_core_seconds == limits.cpu_core_seconds - usage.cpu_core_seconds

    assert status.remaining.memory_mb_seconds ==
             limits.memory_mb_seconds - usage.memory_mb_seconds

    assert status.remaining.disk_gb_seconds == limits.disk_gb_seconds - usage.disk_gb_seconds
    assert status.remaining.billable_units == limits.billable_units - usage.billable_units
  end

  test "build_request_with_quota/3 reserves usage before building request" do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("billing-request"))
    account = user.account

    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 1,
      memory_mb: 512,
      disk_gb: 5,
      ttl_seconds: 30
    }

    opts = [
      limits: %{
        cpu_core_seconds: 10_000,
        memory_mb_seconds: 100_000,
        disk_gb_seconds: 10_000,
        billable_units: 1_000_000
      }
    ]

    assert {:ok, %ProvisioningRequest{}} =
             AgentInfra.build_request_with_quota(account, attrs, opts)
  end
end
