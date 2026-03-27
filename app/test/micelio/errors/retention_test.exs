defmodule Micelio.Errors.RetentionTest do
  use Micelio.DataCase, async: true

  import Ecto.Query, warn: false
  import ExUnit.CaptureLog

  alias Micelio.Errors.Error
  alias Micelio.Errors.Retention
  alias Micelio.Repo

  test "retention cleanup removes resolved and unresolved errors beyond policy" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    resolved_cutoff = DateTime.add(now, -40 * 86_400, :second)
    unresolved_cutoff = DateTime.add(now, -100 * 86_400, :second)

    insert_error(%{
      fingerprint: "resolved-old",
      kind: :exception,
      message: "resolved old",
      severity: :error,
      occurred_at: resolved_cutoff,
      first_seen_at: resolved_cutoff,
      last_seen_at: resolved_cutoff,
      resolved_at: resolved_cutoff
    })

    insert_error(%{
      fingerprint: "resolved-new",
      kind: :exception,
      message: "resolved new",
      severity: :error,
      occurred_at: now,
      first_seen_at: now,
      last_seen_at: now,
      resolved_at: now
    })

    insert_error(%{
      fingerprint: "unresolved-old",
      kind: :exception,
      message: "unresolved old",
      severity: :error,
      occurred_at: unresolved_cutoff,
      first_seen_at: unresolved_cutoff,
      last_seen_at: unresolved_cutoff
    })

    insert_error(%{
      fingerprint: "unresolved-new",
      kind: :exception,
      message: "unresolved new",
      severity: :error,
      occurred_at: now,
      first_seen_at: now,
      last_seen_at: now
    })

    policy = %{
      resolved_retention_days: 30,
      unresolved_retention_days: 90,
      archive_enabled: false,
      archive_prefix: "errors/archives",
      table_warn_threshold: 0
    }

    {result, _log} = with_log(fn -> Retention.run(policy: policy) end)
    assert {:ok, results} = result
    assert results.resolved_deleted == 1
    assert results.unresolved_deleted == 1

    remaining = Repo.aggregate(Error, :count, :id)
    assert remaining == 2

    fingerprints =
      Error
      |> select([error], error.fingerprint)
      |> Repo.all()
      |> Enum.sort()

    assert fingerprints == ["resolved-new", "unresolved-new"]
  end

  test "retention cleanup archives expired errors when enabled" do
    now = ~U[2024-01-01 00:00:00Z]
    resolved_cutoff = DateTime.add(now, -40 * 86_400, :second)
    unresolved_cutoff = DateTime.add(now, -100 * 86_400, :second)

    tmp_dir =
      Path.join(System.tmp_dir!(), "micelio-retention-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    storage_config = [backend: :local, local_path: tmp_dir]

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    insert_error(%{
      fingerprint: "resolved-old",
      kind: :exception,
      message: "resolved old",
      severity: :error,
      occurred_at: resolved_cutoff,
      first_seen_at: resolved_cutoff,
      last_seen_at: resolved_cutoff,
      resolved_at: resolved_cutoff
    })

    insert_error(%{
      fingerprint: "unresolved-old",
      kind: :exception,
      message: "unresolved old",
      severity: :error,
      occurred_at: unresolved_cutoff,
      first_seen_at: unresolved_cutoff,
      last_seen_at: unresolved_cutoff
    })

    policy = %{
      resolved_retention_days: 30,
      unresolved_retention_days: 90,
      archive_enabled: true,
      archive_prefix: "errors/archives",
      table_warn_threshold: 0
    }

    {result, _log} =
      with_log(fn -> Retention.run(policy: policy, now: now, storage_config: storage_config) end)

    assert {:ok, results} = result
    assert results.resolved_archived == 1
    assert results.unresolved_archived == 1
    assert results.resolved_deleted == 1
    assert results.unresolved_deleted == 1

    assert {:ok, files} = Micelio.Storage.list("errors/archives", storage_config: storage_config)
    assert length(files) == 2

    fingerprints =
      files
      |> Enum.map(fn key ->
        {:ok, payload} = Micelio.Storage.get(key, storage_config: storage_config)
        Jason.decode!(payload)
      end)
      |> Enum.flat_map(fn entries -> Enum.map(entries, & &1["fingerprint"]) end)
      |> Enum.sort()

    assert fingerprints == ["resolved-old", "unresolved-old"]
  end

  defp insert_error(attrs) do
    %Error{}
    |> Error.changeset(Map.merge(%{occurrence_count: 1}, attrs))
    |> Repo.insert!()
  end
end
