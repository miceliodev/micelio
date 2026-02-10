defmodule Micelio.Sessions.ChangeStore do
  @moduledoc """
  Persists session changes and updates change filters.
  """

  alias Micelio.Sessions
  alias Micelio.Sessions.Conflict
  alias Micelio.Sessions.Session
  alias Micelio.Storage

  def store_session_changes(%Session{} = session, files, opts \\ []) when is_list(files) do
    stats = %{total: 0, added: 0, modified: 0, deleted: 0}

    changes_attrs =
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

    case Sessions.create_session_changes(changes_attrs) do
      {:ok, changes} ->
        filter =
          changes
          |> Enum.map(& &1.file_path)
          |> Conflict.build_filter()

        case Sessions.update_session(session, %{
               metadata: Map.put(session.metadata || %{}, "change_filter", filter)
             }) do
          {:ok, updated_session} ->
            updated_stats =
              Enum.reduce(changes, stats, fn change, acc ->
                acc
                |> Map.update!(:total, &(&1 + 1))
                |> increment_change_type(change.change_type)
              end)

            {:ok, updated_session, updated_stats}

          {:error, _changeset} ->
            {:error, :session_update_failed}
        end

      {:error, _changeset} ->
        {:error, :change_insert_failed}
    end
  end

  defp increment_change_type(stats, "added"), do: Map.update!(stats, :added, &(&1 + 1))
  defp increment_change_type(stats, "modified"), do: Map.update!(stats, :modified, &(&1 + 1))
  defp increment_change_type(stats, "deleted"), do: Map.update!(stats, :deleted, &(&1 + 1))
  defp increment_change_type(stats, _), do: stats
end
