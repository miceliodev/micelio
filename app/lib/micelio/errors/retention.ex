defmodule Micelio.Errors.Retention do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Micelio.Errors
  alias Micelio.Errors.Config
  alias Micelio.Errors.Error
  alias Micelio.Repo
  alias Micelio.Storage

  require Logger

  @default_archive_prefix "errors/archives"

  def run(opts \\ []) do
    policy = Keyword.get(opts, :policy, Errors.retention_policy())

    now =
      Keyword.get_lazy(opts, :now, fn ->
        DateTime.utc_now() |> DateTime.truncate(:second)
      end)

    {resolved_deleted, resolved_archived} =
      purge_resolved(policy, now, opts)

    {unresolved_deleted, unresolved_archived} =
      purge_unresolved(policy, now, opts)

    total_deleted = resolved_deleted + unresolved_deleted

    maybe_warn_table_size(policy)
    maybe_vacuum(total_deleted)

    {:ok,
     %{
       resolved_deleted: resolved_deleted,
       resolved_archived: resolved_archived,
       unresolved_deleted: unresolved_deleted,
       unresolved_archived: unresolved_archived
     }}
  end

  defp purge_resolved(policy, now, opts) do
    if valid_days?(policy.resolved_retention_days) do
      cutoff = DateTime.add(now, -policy.resolved_retention_days * 86_400, :second)

      query =
        from(error in Error,
          where: not is_nil(error.resolved_at) and error.resolved_at < ^cutoff
        )

      purge(query, policy, "resolved", now, opts)
    else
      {0, 0}
    end
  end

  defp purge_unresolved(policy, now, opts) do
    if valid_days?(policy.unresolved_retention_days) do
      cutoff = DateTime.add(now, -policy.unresolved_retention_days * 86_400, :second)

      query =
        from(error in Error,
          where: is_nil(error.resolved_at) and error.last_seen_at < ^cutoff
        )

      purge(query, policy, "unresolved", now, opts)
    else
      {0, 0}
    end
  end

  defp purge(query, policy, label, now, opts) do
    errors = Repo.all(query)

    archived =
      if policy.archive_enabled and errors != [] do
        archive_errors(errors, label, now, policy, opts)
        Enum.count(errors)
      else
        0
      end

    deleted =
      case errors do
        [] ->
          0

        _ ->
          ids = Enum.map(errors, & &1.id)
          {count, _} = Repo.delete_all(from(error in Error, where: error.id in ^ids))
          count
      end

    {deleted, archived}
  end

  defp archive_errors(errors, label, now, policy, opts) do
    prefix = policy.archive_prefix || Config.retention_archive_prefix() || @default_archive_prefix
    timestamp = DateTime.to_iso8601(now)
    key = "#{String.trim_trailing(prefix, "/")}/#{label}-#{timestamp}.json"

    payload =
      errors
      |> Enum.map(&serialize_error/1)
      |> Jason.encode!()

    case Storage.put(key, payload, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("error retention archive failed: #{inspect(reason)}")
      _ -> :ok
    end
  end

  defp serialize_error(%Error{} = error) do
    %{
      id: error.id,
      fingerprint: error.fingerprint,
      kind: error.kind,
      message: error.message,
      severity: error.severity,
      occurrence_count: error.occurrence_count,
      first_seen_at: error.first_seen_at,
      last_seen_at: error.last_seen_at,
      occurred_at: error.occurred_at,
      resolved_at: error.resolved_at,
      resolved_by_id: error.resolved_by_id,
      metadata: error.metadata,
      context: error.context,
      user_id: error.user_id,
      repository_id: error.repository_id
    }
  end

  defp maybe_vacuum(total_deleted) do
    if total_deleted > 0 and Config.retention_vacuum_enabled?() do
      case vacuum_statement() do
        nil ->
          :ok

        statement ->
          case Repo.query(statement) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning("error retention vacuum failed: #{inspect(reason)}")
          end
      end
    end
  end

  defp vacuum_statement do
    case Repo.__adapter__() do
      Ecto.Adapters.Postgres -> "VACUUM ANALYZE errors"
      _ -> nil
    end
  end

  defp maybe_warn_table_size(policy) do
    threshold = policy.table_warn_threshold || Config.retention_table_warn_threshold()

    if is_integer(threshold) and threshold > 0 do
      count = Repo.aggregate(Error, :count, :id)

      if count > threshold do
        Logger.warning("errors table size warning count=#{count} threshold=#{threshold}")
      end
    end
  end

  defp valid_days?(value), do: is_integer(value) and value > 0
end
