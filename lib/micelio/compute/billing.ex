defmodule Micelio.AgentInfra.Billing do
  @moduledoc """
  Quota and billing tracking for agent provisioning workflows.
  """

  import Ecto.Query

  alias Micelio.Accounts.Account
  alias Micelio.AgentInfra.AgentQuota
  alias Micelio.AgentInfra.AgentUsageEvent
  alias Micelio.AgentInfra.ProvisioningPlan
  alias Micelio.Repo

  @default_limits %{
    cpu_core_seconds: 120_000,
    memory_mb_seconds: 61_440_000,
    disk_gb_seconds: 1_800_000,
    billable_units: 200_000
  }

  @default_weights %{
    cpu_core_second: 1,
    memory_mb_second: 1,
    disk_gb_second: 5
  }

  @default_unit_price_cents 1
  @default_ttl_seconds 3600

  defstruct cpu_core_seconds: 0,
            memory_mb_seconds: 0,
            disk_gb_seconds: 0,
            billable_units: 0,
            cost_cents: 0

  @type usage :: %__MODULE__{
          cpu_core_seconds: non_neg_integer(),
          memory_mb_seconds: non_neg_integer(),
          disk_gb_seconds: non_neg_integer(),
          billable_units: non_neg_integer(),
          cost_cents: non_neg_integer()
        }

  @type quota_status :: %{
          period_start: DateTime.t(),
          period_end: DateTime.t(),
          limits: %{
            cpu_core_seconds: integer() | nil,
            memory_mb_seconds: integer() | nil,
            disk_gb_seconds: integer() | nil,
            billable_units: integer() | nil
          },
          used: %{
            cpu_core_seconds: non_neg_integer(),
            memory_mb_seconds: non_neg_integer(),
            disk_gb_seconds: non_neg_integer(),
            billable_units: non_neg_integer(),
            cost_cents: non_neg_integer()
          },
          remaining: %{
            cpu_core_seconds: integer() | nil,
            memory_mb_seconds: integer() | nil,
            disk_gb_seconds: integer() | nil,
            billable_units: integer() | nil,
            cost_cents: nil
          }
        }

  def usage_from_plan(%ProvisioningPlan{} = plan, opts \\ []) do
    ttl_seconds = plan.ttl_seconds || Keyword.get(opts, :ttl_seconds, default_ttl_seconds())
    cpu_core_seconds = plan.cpu_cores * ttl_seconds
    memory_mb_seconds = plan.memory_mb * ttl_seconds
    disk_gb_seconds = plan.disk_gb * ttl_seconds

    weights = Map.merge(unit_weights(), normalize_weights(Keyword.get(opts, :unit_weights, %{})))

    billable_units =
      cpu_core_seconds * weights.cpu_core_second +
        memory_mb_seconds * weights.memory_mb_second +
        disk_gb_seconds * weights.disk_gb_second

    unit_price_cents = Keyword.get(opts, :unit_price_cents, unit_price_cents())
    cost_cents = billable_units * unit_price_cents

    %__MODULE__{
      cpu_core_seconds: cpu_core_seconds,
      memory_mb_seconds: memory_mb_seconds,
      disk_gb_seconds: disk_gb_seconds,
      billable_units: billable_units,
      cost_cents: cost_cents
    }
  end

  def reserve_for_plan(%Account{} = account, %ProvisioningPlan{} = plan, opts \\ []) do
    usage = usage_from_plan(plan, opts)
    reserve_usage(account.id, usage, opts)
  end

  def reserve_usage(account_id, %__MODULE__{} = usage, opts \\ []) when is_binary(account_id) do
    {period_start, period_end} = quota_period(DateTime.utc_now(), opts)
    limits = Map.merge(default_limits(), normalize_limits(Keyword.get(opts, :limits, %{})))

    Repo.transaction(fn ->
      quota = get_or_create_quota(account_id, period_start, period_end, limits)

      case check_quota(quota, usage) do
        :ok ->
          {:ok, _} =
            quota
            |> AgentQuota.usage_changeset(usage)
            |> Repo.update()

          {:ok, event} =
            %AgentUsageEvent{}
            |> AgentUsageEvent.changeset(%{
              account_id: account_id,
              source: Keyword.get(opts, :source, "provisioning_plan"),
              cpu_core_seconds: usage.cpu_core_seconds,
              memory_mb_seconds: usage.memory_mb_seconds,
              disk_gb_seconds: usage.disk_gb_seconds,
              billable_units: usage.billable_units,
              cost_cents: usage.cost_cents,
              metadata: Keyword.get(opts, :metadata, %{})
            })
            |> Repo.insert()

          event

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def quota_status(account_or_id, opts \\ [])

  def quota_status(%Account{} = account, opts) do
    quota_status(account.id, opts)
  end

  def quota_status(account_id, opts) when is_binary(account_id) do
    {period_start, period_end} = quota_period(DateTime.utc_now(), opts)
    limits = Map.merge(default_limits(), normalize_limits(Keyword.get(opts, :limits, %{})))

    Repo.transaction(fn ->
      get_or_create_quota(account_id, period_start, period_end, limits)
    end)
    |> case do
      {:ok, %AgentQuota{} = quota} ->
        {:ok, quota_status_from_quota(quota)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def quota_period(%DateTime{} = now, opts \\ []) do
    period = Keyword.get(opts, :period, :month)

    case period do
      :month ->
        start_date = Date.beginning_of_month(DateTime.to_date(now))
        end_date = Date.end_of_month(DateTime.to_date(now))

        start = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
        period_end = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
        {start, period_end}

      :day ->
        start = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")
        period_end = DateTime.new!(DateTime.to_date(now), ~T[23:59:59], "Etc/UTC")
        {start, period_end}
    end
  end

  def check_quota(%AgentQuota{} = quota, %__MODULE__{} = usage) do
    exceeded =
      []
      |> maybe_exceed(
        :cpu_core_seconds,
        quota.cpu_core_seconds_used,
        quota.cpu_core_seconds_limit,
        usage.cpu_core_seconds
      )
      |> maybe_exceed(
        :memory_mb_seconds,
        quota.memory_mb_seconds_used,
        quota.memory_mb_seconds_limit,
        usage.memory_mb_seconds
      )
      |> maybe_exceed(
        :disk_gb_seconds,
        quota.disk_gb_seconds_used,
        quota.disk_gb_seconds_limit,
        usage.disk_gb_seconds
      )
      |> maybe_exceed(
        :billable_units,
        quota.billable_units_used,
        quota.billable_units_limit,
        usage.billable_units
      )

    if exceeded == [] do
      :ok
    else
      {:error, {:quota_exceeded, exceeded}}
    end
  end

  def default_limits do
    config = Application.get_env(:micelio, __MODULE__, [])
    Map.merge(@default_limits, normalize_limits(Keyword.get(config, :limits, %{})))
  end

  def unit_weights do
    config = Application.get_env(:micelio, __MODULE__, [])
    Map.merge(@default_weights, normalize_weights(Keyword.get(config, :unit_weights, %{})))
  end

  def unit_price_cents do
    config = Application.get_env(:micelio, __MODULE__, [])
    Keyword.get(config, :unit_price_cents, @default_unit_price_cents)
  end

  def default_ttl_seconds do
    config = Application.get_env(:micelio, __MODULE__, [])
    Keyword.get(config, :default_ttl_seconds, @default_ttl_seconds)
  end

  defp maybe_exceed(exceeded, _field, _used, nil, _delta), do: exceeded

  defp maybe_exceed(exceeded, field, used, limit, delta) do
    if used + delta > limit do
      [field | exceeded]
    else
      exceeded
    end
  end

  defp get_or_create_quota(account_id, period_start, period_end, limits) do
    query =
      from quota in AgentQuota,
        where: quota.account_id == ^account_id and quota.period_start == ^period_start

    case Repo.one(query) do
      %AgentQuota{} = quota ->
        quota

      nil ->
        attrs = %{
          account_id: account_id,
          period_start: period_start,
          period_end: period_end,
          cpu_core_seconds_limit: limits.cpu_core_seconds,
          memory_mb_seconds_limit: limits.memory_mb_seconds,
          disk_gb_seconds_limit: limits.disk_gb_seconds,
          billable_units_limit: limits.billable_units
        }

        case %AgentQuota{}
             |> AgentQuota.create_changeset(attrs)
             |> Repo.insert() do
          {:ok, quota} ->
            quota

          {:error, _changeset} ->
            Repo.one!(query)
        end
    end
  end

  defp quota_status_from_quota(%AgentQuota{} = quota) do
    %{
      period_start: quota.period_start,
      period_end: quota.period_end,
      limits: %{
        cpu_core_seconds: quota.cpu_core_seconds_limit,
        memory_mb_seconds: quota.memory_mb_seconds_limit,
        disk_gb_seconds: quota.disk_gb_seconds_limit,
        billable_units: quota.billable_units_limit
      },
      used: %{
        cpu_core_seconds: quota.cpu_core_seconds_used,
        memory_mb_seconds: quota.memory_mb_seconds_used,
        disk_gb_seconds: quota.disk_gb_seconds_used,
        billable_units: quota.billable_units_used,
        cost_cents: quota.cost_cents_used
      },
      remaining: %{
        cpu_core_seconds:
          remaining_value(quota.cpu_core_seconds_limit, quota.cpu_core_seconds_used),
        memory_mb_seconds:
          remaining_value(quota.memory_mb_seconds_limit, quota.memory_mb_seconds_used),
        disk_gb_seconds: remaining_value(quota.disk_gb_seconds_limit, quota.disk_gb_seconds_used),
        billable_units: remaining_value(quota.billable_units_limit, quota.billable_units_used),
        cost_cents: nil
      }
    }
  end

  defp remaining_value(nil, _used), do: nil

  defp remaining_value(limit, used) do
    max(limit - used, 0)
  end

  defp normalize_limits(limits) when is_list(limits) do
    limits |> Map.new() |> normalize_limits()
  end

  defp normalize_limits(%{} = limits) do
    atom_values =
      Map.take(limits, [:cpu_core_seconds, :memory_mb_seconds, :disk_gb_seconds, :billable_units])

    string_values =
      %{
        cpu_core_seconds: Map.get(limits, "cpu_core_seconds"),
        memory_mb_seconds: Map.get(limits, "memory_mb_seconds"),
        disk_gb_seconds: Map.get(limits, "disk_gb_seconds"),
        billable_units: Map.get(limits, "billable_units")
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(atom_values, string_values)
  end

  defp normalize_weights(weights) when is_list(weights) do
    weights |> Map.new() |> normalize_weights()
  end

  defp normalize_weights(%{} = weights) do
    atom_values = Map.take(weights, [:cpu_core_second, :memory_mb_second, :disk_gb_second])

    string_values =
      %{
        cpu_core_second: Map.get(weights, "cpu_core_second"),
        memory_mb_second: Map.get(weights, "memory_mb_second"),
        disk_gb_second: Map.get(weights, "disk_gb_second")
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(atom_values, string_values)
  end
end
