defmodule Micelio.Sessions.ChangeStore do
  @moduledoc """
  Persists session changes and updates change filters.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Micelio.Repo
  alias Micelio.Sessions
  alias Micelio.Sessions.Conflict
  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  def store_session_changes(%Session{} = session, files, opts \\ []) when is_list(files) do
    stats = build_stats(files)
    changes_attrs = build_change_attrs(session, files, opts)

    case Sessions.create_session_changes(changes_attrs) do
      {:ok, _changes} ->
        case Sessions.update_session(session, %{metadata: draft_metadata(session, changes_attrs)}) do
          {:ok, updated_session} ->
            {:ok, updated_session, stats}

          {:error, _changeset} ->
            {:error, :session_update_failed}
        end

      {:error, _changeset} ->
        {:error, :change_insert_failed}
    end
  end

  def replace_session_changes(%Session{} = session, files, opts \\ []) when is_list(files) do
    stats = build_stats(files)
    changes_attrs = build_change_attrs(session, files, opts)

    Repo.transaction(fn ->
      SessionChange
      |> where([change], change.session_id == ^session.id)
      |> Repo.delete_all()

      changes = insert_changes(changes_attrs)

      case Sessions.update_session(session, %{metadata: draft_metadata(session, changes_attrs)}) do
        {:ok, updated_session} ->
          {updated_session, changes, stats}

        {:error, changeset} ->
          Repo.rollback({:session, changeset})
      end
    end)
    |> case do
      {:ok, {updated_session, _changes, stats}} -> {:ok, updated_session, stats}
      {:error, {:session, %Changeset{}}} -> {:error, :session_update_failed}
      {:error, {:insert, %Changeset{}}} -> {:error, :change_insert_failed}
      {:error, _step, _reason, _changes_so_far} -> {:error, :change_insert_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_changes(changes_attrs) do
    Enum.map(changes_attrs, fn attrs ->
      %SessionChange{}
      |> SessionChange.changeset(attrs)
      |> case do
        %Changeset{} = changeset ->
          case Repo.insert(changeset) do
            {:ok, change} -> change
            {:error, changeset} -> Repo.rollback({:insert, changeset})
          end
      end
    end)
  end

  defp build_change_attrs(%Session{} = session, files, opts) do
    Enum.map(files, fn file ->
      path = Map.get(file, "path")
      content = Map.get(file, "content")
      change_type = Map.get(file, "change_type", "modified")

      {storage_key, inline_content} =
        if content && byte_size(content) > 100_000 do
          key = "sessions/#{session.session_id}/changes/#{path}"
          {:ok, _} = Storage.put(key, content, opts)
          {key, nil}
        else
          {nil, content}
        end

      %{
        session_id: session.id,
        file_path: path,
        change_type: change_type,
        storage_key: storage_key,
        content: inline_content,
        metadata: %{
          size: if(content, do: byte_size(content), else: 0)
        }
      }
    end)
  end

  defp build_stats(files) do
    Enum.reduce(files, %{total: 0, added: 0, modified: 0, deleted: 0}, fn file, acc ->
      acc
      |> Map.update!(:total, &(&1 + 1))
      |> increment_change_type(Map.get(file, "change_type", "modified"))
    end)
  end

  defp draft_metadata(%Session{} = session, changes_attrs) do
    filter =
      changes_attrs
      |> Enum.map(& &1.file_path)
      |> Enum.uniq()
      |> Conflict.build_filter()

    session.metadata
    |> normalize_metadata()
    |> Map.put("change_filter", filter)
    |> Map.delete("virtual_conflict")
  end

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp increment_change_type(stats, "added"), do: Map.update!(stats, :added, &(&1 + 1))
  defp increment_change_type(stats, "modified"), do: Map.update!(stats, :modified, &(&1 + 1))
  defp increment_change_type(stats, "deleted"), do: Map.update!(stats, :deleted, &(&1 + 1))
  defp increment_change_type(stats, _), do: stats
end
