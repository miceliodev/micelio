defmodule Micelio.Sandboxes.Limits do
  @moduledoc """
  Enforces usage limits for sandboxed agentic sessions.

  Limits are configurable via application config:

      config :micelio, Micelio.Sandboxes.Limits,
        max_concurrent_workspaces: 1,
        max_session_duration_minutes: 120,
        max_daily_minutes: 300
  """

  import Ecto.Query, warn: false

  alias Micelio.Repo
  alias Micelio.Sandboxes.UsageRecord

  @doc """
  Checks whether the user can start a new workspace.

  Returns `:ok` or `{:error, reason}`.
  """
  def can_start_workspace?(user_id) do
    today = Date.utc_today()
    record = get_or_init_record(user_id, today)

    cond do
      record.active_workspaces >= max_concurrent_workspaces() ->
        {:error, :max_concurrent_reached}

      record.daily_minutes_used >= max_daily_minutes() ->
        {:error, :daily_limit_reached}

      true ->
        :ok
    end
  end

  @doc """
  Records that a workspace was started for the user.
  """
  def record_workspace_start(user_id) do
    today = Date.utc_today()

    Repo.insert(
      %UsageRecord{user_id: user_id, date: today, active_workspaces: 1, daily_minutes_used: 0},
      on_conflict: [inc: [active_workspaces: 1]],
      conflict_target: [:user_id, :date]
    )
  end

  @doc """
  Records that a workspace was stopped and adds the duration to daily usage.
  """
  def record_workspace_stop(user_id, duration_minutes) do
    today = Date.utc_today()
    duration_minutes = max(duration_minutes, 0)

    Repo.insert(
      %UsageRecord{
        user_id: user_id,
        date: today,
        active_workspaces: 0,
        daily_minutes_used: duration_minutes
      },
      on_conflict: [inc: [active_workspaces: -1, daily_minutes_used: duration_minutes]],
      conflict_target: [:user_id, :date]
    )
  end

  @doc """
  Returns the number of active workspaces for a user.
  """
  def active_workspace_count(user_id) do
    today = Date.utc_today()

    UsageRecord
    |> where([r], r.user_id == ^user_id and r.date == ^today)
    |> select([r], r.active_workspaces)
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Returns minutes used today for a user.
  """
  def daily_minutes_used(user_id) do
    today = Date.utc_today()

    UsageRecord
    |> where([r], r.user_id == ^user_id and r.date == ^today)
    |> select([r], r.daily_minutes_used)
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Resets active workspace count to 0 for a user. Used when cleaning up stale sessions
  after server restarts where the agent process is no longer running.
  """
  def reset_active_workspaces(user_id) do
    today = Date.utc_today()

    UsageRecord
    |> where([r], r.user_id == ^user_id and r.date == ^today)
    |> Repo.update_all(set: [active_workspaces: 0])
  end

  @doc """
  Checks whether a sandbox session has exceeded its maximum duration.
  """
  def session_expired?(%{sandbox_started_at: nil}), do: false

  def session_expired?(%{sandbox_started_at: started_at}) do
    max_seconds = max_session_duration_minutes() * 60
    DateTime.diff(DateTime.utc_now(), started_at, :second) > max_seconds
  end

  # --- Configuration ---

  def max_concurrent_workspaces do
    config(:max_concurrent_workspaces, 1)
  end

  def max_session_duration_minutes do
    config(:max_session_duration_minutes, 120)
  end

  def max_daily_minutes do
    config(:max_daily_minutes, 300)
  end

  defp config(key, default) do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp get_or_init_record(user_id, date) do
    UsageRecord
    |> where([r], r.user_id == ^user_id and r.date == ^date)
    |> Repo.one()
    |> case do
      nil ->
        %UsageRecord{user_id: user_id, date: date, active_workspaces: 0, daily_minutes_used: 0}

      record ->
        record
    end
  end
end
