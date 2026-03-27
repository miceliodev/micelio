defmodule Micelio.Mic.Landing do
  @moduledoc """
  Coordinator-free landing using compare-and-swap semantics.
  """

  alias Micelio.Mic.{
    Binary,
    ConflictIndex,
    DeltaCompression,
    RollupWorker,
    SearchIndex,
    Tree
  }

  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Sessions.Conflict
  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  require Logger

  @max_retries 8
  @backoff_base_ms 20
  @zero_hash Binary.zero_hash()

  def land_session(%Session{} = session, opts \\ []) do
    repository = Repositories.get_repository_with_organization(session.repository_id)
    tree_hash = Keyword.get(opts, :tree_hash)
    change_filter = Map.get(session.metadata || %{}, "change_filter")

    do_land(session, repository, tree_hash, change_filter, 0, opts)
  end

  defp do_land(session, repository, tree_hash, change_filter, attempt, opts)
       when attempt <= @max_retries do
    Logger.debug("mic.land start session=#{session.session_id} attempt=#{attempt}")

    head_key = head_key(repository.id)

    landed_at_ms = System.system_time(:millisecond)
    landed_at = DateTime.from_unix!(div(landed_at_ms, 1000))

    with {:ok, current_head, current_etag} <- fetch_head(head_key, opts),
         :ok <-
           check_conflicts(session, repository.id, current_head.position, change_filter, opts),
         {:ok, computed_tree_hash} <-
           build_tree_hash(session, repository.id, current_head.tree_hash, tree_hash, opts),
         next_position = current_head.position + 1,
         head_binary = Binary.encode_head(Binary.new_head(next_position, computed_tree_hash)),
         {:ok, _} <- write_head(head_key, head_binary, current_etag, opts),
         landing_binary =
           encode_landing(session, next_position, computed_tree_hash, change_filter, landed_at_ms),
         {:ok, _} <-
           Storage.put(landing_key(repository.id, next_position), landing_binary, opts),
         :ok <-
           ConflictIndex.store_path_index(
             repository.id,
             next_position,
             list_change_paths(session),
             opts
           ),
         :ok <- index_search(repository.id, computed_tree_hash, landed_at_ms, session, opts),
         :ok <- RollupWorker.enqueue(repository.id, next_position, change_filter, opts),
         {:ok, _} <- store_session_summary(session, repository.id, landed_at_ms, opts) do
      {:ok, %{position: next_position, tree_hash: computed_tree_hash, landed_at: landed_at}}
    else
      {:error, :not_found} ->
        create_first_head(session, repository.id, tree_hash, change_filter, attempt, opts)

      {:error, :precondition_failed} ->
        retry(session, tree_hash, change_filter, attempt, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_land(_session, _repository, _tree_hash, _change_filter, _attempt, _opts),
    do: {:error, :landing_retry_exhausted}

  defp create_first_head(session, repository_id, tree_hash, change_filter, attempt, opts) do
    head_key = head_key(repository_id)
    position = 1
    landed_at_ms = System.system_time(:millisecond)
    landed_at = DateTime.from_unix!(div(landed_at_ms, 1000))

    {:ok, computed_tree_hash} =
      build_tree_hash(session, repository_id, Binary.zero_hash(), tree_hash, opts)

    head_binary = Binary.encode_head(Binary.new_head(position, computed_tree_hash))

    case Storage.put_if_none_match(head_key, head_binary, opts) do
      {:ok, _} ->
        landing_binary =
          encode_landing(session, position, computed_tree_hash, change_filter, landed_at_ms)

        with {:ok, _} <- Storage.put(landing_key(repository_id, position), landing_binary, opts),
             :ok <-
               ConflictIndex.store_path_index(
                 repository_id,
                 position,
                 list_change_paths(session),
                 opts
               ),
             :ok <- index_search(repository_id, computed_tree_hash, landed_at_ms, session, opts),
             :ok <- RollupWorker.enqueue(repository_id, position, change_filter, opts),
             {:ok, _} <- store_session_summary(session, repository_id, landed_at_ms, opts) do
          {:ok, %{position: position, tree_hash: computed_tree_hash, landed_at: landed_at}}
        end

      {:error, :precondition_failed} ->
        retry(session, tree_hash, change_filter, attempt, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry(session, tree_hash, change_filter, attempt, opts) do
    backoff = @backoff_base_ms * (attempt + 1)
    Process.sleep(backoff)

    repository = Repositories.get_repository_with_organization(session.repository_id)
    do_land(session, repository, tree_hash, change_filter, attempt + 1, opts)
  end

  defp fetch_head(head_key, opts) do
    case Storage.get_with_metadata(head_key, opts) do
      {:ok, %{content: content, etag: etag}} ->
        with {:ok, head} <- Binary.decode_head(content),
             true <- not is_nil(etag) do
          {:ok, head, etag}
        else
          false -> {:error, :missing_etag}
          {:error, _} = error -> error
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_head(head_key, content, etag, opts) when is_binary(etag) do
    Storage.put_if_match(head_key, content, etag, opts)
  end

  defp write_head(head_key, content, nil, opts) do
    Storage.put_if_none_match(head_key, content, opts)
  end

  defp encode_landing(session, position, tree_hash, change_filter, landed_at_ms) do
    Binary.encode_landing(%{
      position: position,
      landed_at_ms: landed_at_ms,
      tree_hash: tree_hash,
      session_id: session.session_id,
      change_filter: change_filter
    })
  end

  defp store_session_summary(session, repository_id, landed_at_ms, opts) do
    summary =
      Binary.encode_session_summary(%{
        session_id: session.session_id,
        repository_id: repository_id,
        user_id: session.user_id,
        goal: session.goal,
        status: "landed",
        started_at_ms: datetime_ms(session.started_at),
        landed_at_ms: landed_at_ms,
        conversation_count: length(session.conversation || []),
        decisions_count: length(session.decisions || [])
      })

    Storage.put(session_summary_key(repository_id, session.session_id), summary, opts)
  end

  defp datetime_ms(nil), do: 0

  defp datetime_ms(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  defp head_key(repository_id), do: "repositories/#{repository_id}/head"

  defp landing_key(repository_id, position),
    do: "repositories/#{repository_id}/landing/#{pad_position(position)}.bin"

  defp session_summary_key(repository_id, session_id),
    do: "repositories/#{repository_id}/sessions/#{session_id}.bin"

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp tree_key(repository_id, tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/trees/#{prefix}/#{hash_hex}.bin"
  end

  defp blob_key(repository_id, blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/blobs/#{prefix}/#{hash_hex}.bin"
  end

  defp build_tree_hash(session, repository_id, base_tree_hash, override_tree_hash, opts) do
    tree_hash =
      case override_tree_hash do
        nil -> nil
        hash when is_binary(hash) -> hash
      end

    if tree_hash do
      {:ok, tree_hash}
    else
      base_tree = load_tree(repository_id, base_tree_hash, opts)
      changes = Sessions.list_session_changes(session)

      with {:ok, updated_tree} <- apply_changes(base_tree, repository_id, changes, opts) do
        encoded_tree = Tree.encode(updated_tree)
        tree_hash = Tree.hash(encoded_tree)
        _ = store_tree(repository_id, tree_hash, encoded_tree, opts)
        {:ok, tree_hash}
      end
    end
  end

  defp load_tree(_repository_id, tree_hash, _opts) when tree_hash == @zero_hash, do: Tree.empty()

  defp load_tree(repository_id, tree_hash, opts) do
    case Storage.get(tree_key(repository_id, tree_hash), opts) do
      {:ok, content} ->
        case Tree.decode(content) do
          {:ok, tree} -> tree
          {:error, _} -> Tree.empty()
        end

      {:error, _} ->
        Tree.empty()
    end
  end

  defp store_tree(repository_id, tree_hash, encoded_tree, opts) do
    case Storage.put_if_none_match(tree_key(repository_id, tree_hash), encoded_tree, opts) do
      {:ok, _} -> :ok
      {:error, :precondition_failed} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_changes(tree, repository_id, changes, opts) do
    Enum.reduce_while(changes, {:ok, tree}, fn %SessionChange{} = change, {:ok, acc} ->
      case apply_change(acc, repository_id, change, opts) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_change(
         tree,
         _repository_id,
         %SessionChange{change_type: "deleted", file_path: path},
         _opts
       ) do
    {:ok, Tree.delete(tree, path)}
  end

  defp apply_change(tree, repository_id, %SessionChange{} = change, opts) do
    with {:ok, content} <- load_change_content(change, opts),
         blob_hash = :crypto.hash(:sha256, content),
         base_hash = Map.get(tree, change.file_path),
         :ok <- store_blob(repository_id, blob_hash, content, base_hash, opts) do
      {:ok, Tree.put(tree, change.file_path, blob_hash)}
    end
  end

  defp check_conflicts(%Session{} = session, repository_id, current_position, change_filter, opts) do
    base_position = parse_base_position(session.metadata)

    if base_position >= current_position or is_nil(change_filter) do
      :ok
    else
      paths =
        session
        |> Sessions.list_session_changes()
        |> Enum.map(& &1.file_path)
        |> Enum.uniq()

      if paths == [] do
        :ok
      else
        scan_ranges =
          ConflictIndex.expand_ranges(
            repository_id,
            base_position + 1,
            current_position,
            paths,
            opts
          )

        Logger.debug(
          "mic.conflict_check ranges=#{length(scan_ranges)} paths=#{length(paths)} project=#{repository_id}"
        )

        :telemetry.execute(
          [:micelio, :mic, :conflict_check],
          %{scan_ranges: length(scan_ranges), paths: length(paths)},
          %{repository_id: repository_id}
        )

        conflicts = detect_conflicts(repository_id, scan_ranges, paths, opts)

        if conflicts == [] do
          :ok
        else
          Logger.debug(
            "mic.conflict_check conflict_count=#{length(conflicts)} project=#{repository_id}"
          )

          {:error, {:conflicts, conflicts}}
        end
      end
    end
  end

  defp parse_base_position(%{"base_position" => value}) when is_integer(value), do: value

  defp parse_base_position(%{"base_position" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {position, _} -> position
      _ -> 0
    end
  end

  defp parse_base_position(_), do: 0

  defp detect_conflicts(_repository_id, [], _paths, _opts), do: []

  defp detect_conflicts(repository_id, ranges, paths, opts) do
    Enum.reduce_while(ranges, [], fn {from_pos, to_pos}, acc ->
      case find_conflicts_in_range(repository_id, from_pos, to_pos, paths, opts) do
        [] -> {:cont, acc}
        conflicts -> {:halt, Enum.uniq(acc ++ conflicts)}
      end
    end)
  end

  defp find_conflicts_in_range(repository_id, from_pos, to_pos, paths, opts) do
    Enum.reduce_while(from_pos..to_pos, [], fn position, acc ->
      case ConflictIndex.load_path_index(repository_id, position, opts) do
        {:ok, nil} ->
          case ConflictIndex.load_landing_filter(repository_id, position, opts) do
            {:ok, nil} ->
              {:cont, acc}

            {:ok, {_session_id, filter}} ->
              if any_conflicts?(paths, filter) do
                {:halt, Enum.uniq(acc ++ paths)}
              else
                {:cont, acc}
              end

            {:error, _} ->
              {:halt, Enum.uniq(acc ++ paths)}
          end

        {:ok, indexed_paths} ->
          matches = Enum.filter(paths, &Enum.member?(indexed_paths, &1))

          if matches == [] do
            {:cont, acc}
          else
            {:halt, Enum.uniq(acc ++ matches)}
          end

        {:error, _} ->
          {:halt, Enum.uniq(acc ++ paths)}
      end
    end)
  end

  defp any_conflicts?(paths, nil) when is_list(paths), do: paths != []

  defp any_conflicts?(paths, filter) when is_list(paths) do
    Enum.any?(paths, fn path -> Conflict.might_conflict?(filter, path) end)
  end

  defp list_change_paths(session) do
    session
    |> Sessions.list_session_changes()
    |> Enum.map(& &1.file_path)
    |> Enum.uniq()
  end

  defp index_search(repository_id, revision_hash, landed_at_ms, session, opts) do
    changes = Sessions.list_session_changes(session)

    :ok =
      SearchIndex.index_session_changes(
        repository_id,
        revision_hash,
        landed_at_ms,
        session,
        changes,
        opts
      )

    SearchIndex.store_revision_metadata(repository_id, revision_hash, landed_at_ms, opts)
  end

  defp load_change_content(%SessionChange{content: content}, _opts) when is_binary(content) do
    {:ok, content}
  end

  defp load_change_content(%SessionChange{storage_key: key}, opts) when is_binary(key) do
    Storage.get(key, opts)
  end

  defp load_change_content(_, _opts), do: {:error, :missing_change_content}

  defp store_blob(repository_id, blob_hash, content, base_hash, opts) do
    payload =
      with base_hash when is_binary(base_hash) <- base_hash,
           true <- base_hash != blob_hash,
           {:ok, base_payload} <- Storage.get(blob_key(repository_id, base_hash), opts),
           {:ok, base_content} <-
             DeltaCompression.decode(base_payload, fn hash ->
               Storage.get(blob_key(repository_id, hash), opts)
             end),
           {:ok, delta_payload} <-
             DeltaCompression.maybe_encode(base_hash, base_content, content) do
        delta_payload
      else
        _ -> content
      end

    case Storage.put_if_none_match(blob_key(repository_id, blob_hash), payload, opts) do
      {:ok, _} -> :ok
      {:error, :precondition_failed} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
