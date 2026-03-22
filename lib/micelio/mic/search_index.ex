defmodule Micelio.Mic.SearchIndex do
  @moduledoc """
  Repository-scoped text search index used by `hif.v1.SearchService`.

  The hot path is optimized for the latest indexed revision, which is the only
  revision currently served remotely without a rebuild. Search snapshots are
  maintained incrementally per landed session and queried through a repository-
  scoped inverted index instead of append-only JSON posting lists.
  """

  alias Micelio.Accounts
  alias Micelio.Mic.Binary
  alias Micelio.Mic.Project
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  @token_regex ~r/[A-Za-z0-9_]{2,}/u
  @zero_hash Binary.zero_hash()
  @cache_table __MODULE__.Cache
  @index_version 2
  @root_bucket "__root__"

  @type posting :: %{
          path: String.t(),
          line: non_neg_integer(),
          column: non_neg_integer(),
          snippet: String.t(),
          session_id: String.t(),
          attributed_to_handle: String.t(),
          revision_hash: binary(),
          landed_at_ms: non_neg_integer()
        }

  @type stored_posting :: %{
          line: non_neg_integer(),
          column: non_neg_integer(),
          snippet: String.t(),
          session_id: String.t(),
          attributed_to_handle: String.t(),
          landed_at_ms: non_neg_integer()
        }

  @type file_snapshot :: %{
          path: String.t(),
          bucket: String.t(),
          tokens: %{optional(String.t()) => [stored_posting()]}
        }

  @type token_meta :: %{
          posting_count: non_neg_integer(),
          buckets: %{optional(String.t()) => non_neg_integer()}
        }

  @spec index_session_changes(
          binary(),
          binary(),
          non_neg_integer(),
          map(),
          [SessionChange.t()],
          keyword()
        ) ::
          :ok | {:error, term()}
  def index_session_changes(
        repository_id,
        revision_hash,
        landed_at_ms,
        session,
        changes,
        opts \\ []
      )
      when is_binary(repository_id) and is_binary(revision_hash) and
             byte_size(revision_hash) == 32 and is_integer(landed_at_ms) and landed_at_ms >= 0 and
             is_list(changes) do
    attributed_to_handle = resolve_attributed_to_handle(session)
    changes = collapse_changes(changes)

    with :ok <- acquire_update_lock(repository_id, opts) do
      try do
        {file_updates, token_updates} =
          prepare_updates(
            repository_id,
            changes,
            session.session_id,
            attributed_to_handle,
            landed_at_ms,
            opts
          )

        with :ok <- apply_token_updates(repository_id, token_updates, opts),
             :ok <- apply_file_updates(repository_id, file_updates, opts) do
          update_index_metadata(repository_id, revision_hash, opts)
        end
      after
        _ = release_update_lock(repository_id, opts)
        evict_cache()
      end
    end
  end

  @spec query(binary(), map(), keyword()) ::
          {:ok,
           %{total: non_neg_integer(), matches: [posting()], next_offset: non_neg_integer() | nil}}
          | {:error, term()}
  def query(repository_id, params, opts \\ []) when is_binary(repository_id) and is_map(params) do
    at_revision_hash = Map.get(params, :at_revision_hash)
    path_prefix = normalize_blank(Map.get(params, :path_prefix))
    path_glob = normalize_blank(Map.get(params, :path_glob))
    regex? = Map.get(params, :regex, false)
    case_sensitive? = Map.get(params, :case_sensitive, false)
    limit = Map.get(params, :limit, 20) |> normalize_limit()
    offset = Map.get(params, :offset, 0) |> normalize_offset()
    query = Map.get(params, :query, "")

    with {:ok, query_revision_hash} <-
           resolve_revision_hash(repository_id, at_revision_hash, opts),
         {:ok, matcher} <- build_matcher(query, regex?, case_sensitive?) do
      tokens = candidate_tokens(query)

      if tokens == [] do
        scan_repository(
          repository_id,
          query_revision_hash,
          matcher,
          path_prefix,
          path_glob,
          limit,
          offset,
          opts
        )
      else
        with :ok <- ensure_not_updating(repository_id, opts),
             :ok <- ensure_index_fresh(repository_id, query_revision_hash, opts) do
          query_index(
            repository_id,
            query_revision_hash,
            tokens,
            matcher,
            path_prefix,
            path_glob,
            limit,
            offset,
            opts
          )
        end
      end
    end
  end

  @spec store_revision_metadata(binary(), binary(), non_neg_integer(), keyword()) ::
          :ok | {:error, term()}
  def store_revision_metadata(repository_id, revision_hash, landed_at_ms, opts \\ [])
      when is_binary(repository_id) and is_binary(revision_hash) and
             byte_size(revision_hash) == 32 and is_integer(landed_at_ms) and landed_at_ms >= 0 do
    payload =
      Jason.encode!(%{
        "landed_at_ms" => landed_at_ms,
        "revision_hash" => Base.encode16(revision_hash, case: :lower)
      })

    case Storage.put(landing_metadata_key(repository_id, revision_hash), payload, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_updates(
         repository_id,
         changes,
         session_id,
         attributed_to_handle,
         landed_at_ms,
         opts
       ) do
    Enum.reduce(changes, {%{}, %{}}, fn %SessionChange{} = change,
                                        {file_updates, token_updates} ->
      path = normalize_file_path(change.file_path)
      old_snapshot = load_file_snapshot(repository_id, path, opts)

      new_snapshot =
        build_file_snapshot(
          change,
          path,
          session_id,
          attributed_to_handle,
          landed_at_ms,
          opts
        )

      file_updates =
        case {old_snapshot, new_snapshot} do
          {nil, nil} -> file_updates
          _ -> Map.put(file_updates, path, {old_snapshot, new_snapshot})
        end

      token_updates = accumulate_token_updates(token_updates, path, old_snapshot, new_snapshot)
      {file_updates, token_updates}
    end)
  end

  defp accumulate_token_updates(token_updates, path, old_snapshot, new_snapshot) do
    old_tokens = old_snapshot |> snapshot_tokens() |> Map.keys() |> MapSet.new()
    new_tokens = new_snapshot |> snapshot_tokens() |> Map.keys() |> MapSet.new()
    affected_tokens = MapSet.union(old_tokens, new_tokens)

    Enum.reduce(affected_tokens, token_updates, fn token, acc ->
      old_bucket = snapshot_bucket(old_snapshot, path)
      new_bucket = snapshot_bucket(new_snapshot, path)
      old_postings = get_snapshot_postings(old_snapshot, token)
      new_postings = get_snapshot_postings(new_snapshot, token)

      acc
      |> put_token_update(token, old_bucket, path, old_postings, [])
      |> put_token_update(token, new_bucket, path, [], new_postings)
    end)
  end

  defp put_token_update(acc, _token, _bucket, _path, [], []), do: acc

  defp put_token_update(acc, token, bucket, path, old_postings, new_postings) do
    update_in(acc, [Access.key(token, %{}), Access.key(bucket, %{})], fn bucket_updates ->
      Map.update(
        bucket_updates || %{},
        path,
        %{old: old_postings, new: new_postings},
        fn existing ->
          %{
            old: if(old_postings == [], do: existing.old, else: old_postings),
            new: if(new_postings == [], do: existing.new, else: new_postings)
          }
        end
      )
    end)
  end

  defp apply_token_updates(repository_id, token_updates, opts) do
    Enum.reduce_while(token_updates, :ok, fn {token, bucket_updates}, :ok ->
      case apply_token_update(repository_id, token, bucket_updates, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_token_update(repository_id, token, bucket_updates, opts) do
    meta = load_token_meta(repository_id, token, opts) || %{posting_count: 0, buckets: %{}}

    result =
      Enum.reduce_while(bucket_updates, {meta, :ok}, fn {bucket, path_updates},
                                                        {current_meta, :ok} ->
        case apply_token_bucket_update(
               repository_id,
               token,
               bucket,
               path_updates,
               current_meta,
               opts
             ) do
          {:ok, next_meta} -> {:cont, {next_meta, :ok}}
          {:error, reason} -> {:halt, {current_meta, {:error, reason}}}
        end
      end)

    case result do
      {_meta, {:error, reason}} ->
        {:error, reason}

      {%{posting_count: 0}, :ok} ->
        delete_token_meta(repository_id, token, opts)

      {next_meta, :ok} ->
        store_token_meta(repository_id, token, next_meta, opts)
    end
  end

  defp apply_token_bucket_update(repository_id, token, bucket, path_updates, meta, opts) do
    bucket_entries = load_token_bucket(repository_id, token, bucket, opts) || %{}
    bucket_count = Map.get(meta.buckets, bucket, count_bucket_entries(bucket_entries))

    delta =
      Enum.reduce(path_updates, 0, fn {_path, %{old: old_postings, new: new_postings}}, acc ->
        acc + length(new_postings) - length(old_postings)
      end)

    updated_entries =
      Enum.reduce(path_updates, bucket_entries, fn {path, %{new: new_postings}}, acc ->
        if new_postings == [] do
          Map.delete(acc, path)
        else
          Map.put(acc, path, new_postings)
        end
      end)

    new_bucket_count = max(bucket_count + delta, 0)

    with :ok <- persist_token_bucket(repository_id, token, bucket, updated_entries, opts) do
      updated_buckets =
        if new_bucket_count == 0 do
          Map.delete(meta.buckets, bucket)
        else
          Map.put(meta.buckets, bucket, new_bucket_count)
        end

      {:ok,
       %{
         posting_count: max(meta.posting_count + delta, 0),
         buckets: updated_buckets
       }}
    end
  end

  defp apply_file_updates(repository_id, file_updates, opts) do
    Enum.reduce_while(file_updates, :ok, fn {path, {old_snapshot, new_snapshot}}, :ok ->
      result =
        case {old_snapshot, new_snapshot} do
          {nil, nil} ->
            :ok

          {_old, nil} ->
            delete_file_snapshot(repository_id, path, opts)

          {_old, snapshot} ->
            store_file_snapshot(repository_id, path, snapshot, opts)
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_file_snapshot(
         %SessionChange{change_type: type},
         _path,
         _session_id,
         _attributed_to_handle,
         _landed_at_ms,
         _opts
       )
       when type in ["deleted", "renamed"], do: nil

  defp build_file_snapshot(
         %SessionChange{} = change,
         path,
         session_id,
         attributed_to_handle,
         landed_at_ms,
         opts
       ) do
    case load_change_content(change, opts) do
      {:ok, content} when is_binary(content) ->
        tokens =
          build_postings_by_token(
            content,
            session_id,
            attributed_to_handle,
            landed_at_ms
          )

        if map_size(tokens) != 0 do
          %{
            path: path,
            bucket: bucket_for_path(path),
            tokens: tokens
          }
        end

      _ ->
        nil
    end
  end

  defp build_postings_by_token(content, session_id, attributed_to_handle, landed_at_ms)
       when is_binary(content) do
    if String.valid?(content) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {line, line_number}, acc ->
        Regex.scan(@token_regex, line, return: :index)
        |> Enum.reduce(acc, fn [{column, length}], token_acc ->
          token = String.slice(line, column, length) |> String.downcase()

          posting = %{
            line: line_number,
            column: column + 1,
            snippet: String.slice(line, 0, 400),
            session_id: session_id,
            attributed_to_handle: attributed_to_handle,
            landed_at_ms: landed_at_ms
          }

          Map.update(token_acc, token, [posting], fn existing -> [posting | existing] end)
        end)
      end)
      |> Map.new(fn {token, postings} ->
        {token, Enum.sort_by(postings, fn posting -> {posting.line, posting.column} end)}
      end)
    else
      %{}
    end
  end

  defp query_index(
         repository_id,
         revision_hash,
         tokens,
         matcher,
         path_prefix,
         path_glob,
         limit,
         offset,
         opts
       ) do
    case select_anchor_token(repository_id, revision_hash, tokens, opts) do
      {:ok, nil} ->
        {:ok, %{total: 0, matches: [], next_offset: nil}}

      {:ok, {anchor_token, anchor_meta}} ->
        bucket_names = candidate_buckets(anchor_meta, path_prefix)

        postings =
          load_anchor_postings(repository_id, revision_hash, anchor_token, bucket_names, opts)

        matches =
          postings
          |> Enum.filter(&path_matches?(&1.path, path_prefix, path_glob))
          |> Enum.filter(&matcher_matches?(matcher, &1.snippet))
          |> Enum.sort_by(fn posting -> {posting.path, posting.line, posting.column} end)

        total = length(matches)
        paged = matches |> Enum.drop(offset) |> Enum.take(limit)
        next_offset = if offset + limit < total, do: offset + limit

        {:ok, %{total: total, matches: paged, next_offset: next_offset}}
    end
  end

  defp scan_repository(
         repository_id,
         revision_hash,
         matcher,
         path_prefix,
         path_glob,
         limit,
         offset,
         opts
       ) do
    with {:ok, tree} <- Project.get_tree(repository_id, revision_hash, opts) do
      matches =
        tree
        |> Enum.sort_by(fn {path, _hash} -> path end)
        |> Enum.flat_map(fn {path, blob_hash} ->
          if path_matches?(path, path_prefix, path_glob) do
            blob_matches(repository_id, path, blob_hash, matcher, revision_hash, opts)
          else
            []
          end
        end)

      total = length(matches)
      paged = matches |> Enum.drop(offset) |> Enum.take(limit)
      next_offset = if offset + limit < total, do: offset + limit

      {:ok, %{total: total, matches: paged, next_offset: next_offset}}
    end
  end

  defp blob_matches(repository_id, path, blob_hash, matcher, revision_hash, opts) do
    case Project.get_blob(repository_id, blob_hash, opts) do
      {:ok, content} when is_binary(content) ->
        if String.valid?(content) do
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(fn {line, line_number} ->
            case matcher_column(matcher, line) do
              nil ->
                []

              column ->
                [
                  %{
                    path: path,
                    line: line_number,
                    column: column,
                    snippet: String.slice(line, 0, 400),
                    session_id: "",
                    attributed_to_handle: "",
                    revision_hash: revision_hash,
                    landed_at_ms: 0
                  }
                ]
            end
          end)
        else
          []
        end

      _ ->
        []
    end
  end

  defp select_anchor_token(repository_id, revision_hash, tokens, opts) do
    token_metas =
      Enum.map(tokens, fn token ->
        {token, cached_token_meta(repository_id, revision_hash, token, opts)}
      end)

    if Enum.any?(token_metas, fn {_token, meta} -> is_nil(meta) or meta.posting_count == 0 end) do
      {:ok, nil}
    else
      {anchor_token, meta} =
        Enum.min_by(token_metas, fn {_token, meta} ->
          {meta.posting_count, map_size(meta.buckets)}
        end)

      {:ok, {anchor_token, meta}}
    end
  end

  defp load_anchor_postings(repository_id, revision_hash, token, bucket_names, opts) do
    Enum.flat_map(bucket_names, fn bucket ->
      repository_id
      |> cached_token_bucket(revision_hash, token, bucket, opts)
      |> Enum.flat_map(fn {path, postings} ->
        Enum.map(postings, fn posting ->
          %{
            path: path,
            line: posting.line,
            column: posting.column,
            snippet: posting.snippet,
            session_id: posting.session_id,
            attributed_to_handle: posting.attributed_to_handle,
            revision_hash: revision_hash,
            landed_at_ms: posting.landed_at_ms
          }
        end)
      end)
    end)
  end

  defp candidate_buckets(%{buckets: buckets}, nil), do: Map.keys(buckets)

  defp candidate_buckets(%{buckets: buckets}, path_prefix) do
    bucket = bucket_for_prefix(path_prefix)

    if Map.has_key?(buckets, bucket) do
      [bucket]
    else
      []
    end
  end

  defp cached_token_meta(repository_id, revision_hash, token, opts) do
    cache_fetch({:token_meta, repository_id, revision_hash, token}, fn ->
      load_token_meta(repository_id, token, opts)
    end)
  end

  defp cached_token_bucket(repository_id, revision_hash, token, bucket, opts) do
    cache_fetch({:token_bucket, repository_id, revision_hash, token, bucket}, fn ->
      load_token_bucket(repository_id, token, bucket, opts) || %{}
    end)
  end

  defp cache_fetch(key, loader) do
    ensure_cache_table()

    case :ets.lookup(@cache_table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = loader.()
        :ets.insert(@cache_table, {key, value})
        value
    end
  end

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])

      _ ->
        @cache_table
    end
  end

  defp evict_cache do
    ensure_cache_table()
    :ets.delete_all_objects(@cache_table)
    :ok
  end

  defp ensure_not_updating(repository_id, opts) do
    if Storage.exists?(update_lock_key(repository_id), opts) do
      {:error, :index_updating}
    else
      :ok
    end
  end

  defp acquire_update_lock(repository_id, opts) do
    case Storage.put_if_none_match(update_lock_key(repository_id), "updating", opts) do
      {:ok, _} -> :ok
      {:error, :precondition_failed} -> {:error, :index_updating}
      {:error, reason} -> {:error, reason}
    end
  end

  defp release_update_lock(repository_id, opts) do
    case Storage.delete(update_lock_key(repository_id), opts) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_index_metadata(repository_id, revision_hash, opts) do
    payload =
      encode_term(%{
        version: @index_version,
        indexed_revision_hash: revision_hash,
        updated_at_ms: System.system_time(:millisecond)
      })

    case Storage.put(current_meta_key(repository_id), payload, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_index_fresh(_repository_id, latest_revision_hash, _opts)
       when is_binary(latest_revision_hash) and latest_revision_hash == @zero_hash, do: :ok

  defp ensure_index_fresh(repository_id, latest_revision_hash, opts) do
    indexed_revision_hash = load_index_revision_hash(repository_id, opts)

    if indexed_revision_hash == latest_revision_hash do
      :ok
    else
      {:error, :stale_index}
    end
  end

  defp load_index_revision_hash(repository_id, opts) do
    case Storage.get(current_meta_key(repository_id), opts) do
      {:ok, body} ->
        case decode_term(body) do
          {:ok, %{indexed_revision_hash: revision_hash}} when is_binary(revision_hash) ->
            revision_hash

          _ ->
            Binary.zero_hash()
        end

      _ ->
        Binary.zero_hash()
    end
  end

  defp load_file_snapshot(repository_id, path, opts) do
    case Storage.get(file_snapshot_key(repository_id, path), opts) do
      {:ok, body} ->
        case decode_term(body) do
          {:ok, %{path: ^path, bucket: bucket, tokens: tokens}} when is_map(tokens) ->
            %{path: path, bucket: bucket, tokens: tokens}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp store_file_snapshot(repository_id, path, snapshot, opts) do
    case Storage.put(file_snapshot_key(repository_id, path), encode_term(snapshot), opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_file_snapshot(repository_id, path, opts) do
    case Storage.delete(file_snapshot_key(repository_id, path), opts) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_token_meta(repository_id, token, opts) do
    case Storage.get(token_meta_key(repository_id, token), opts) do
      {:ok, body} ->
        case decode_term(body) do
          {:ok, %{posting_count: posting_count, buckets: buckets}}
          when is_integer(posting_count) and is_map(buckets) ->
            %{posting_count: posting_count, buckets: buckets}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp store_token_meta(repository_id, token, meta, opts) do
    case Storage.put(token_meta_key(repository_id, token), encode_term(meta), opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_token_meta(repository_id, token, opts) do
    case Storage.delete(token_meta_key(repository_id, token), opts) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_token_bucket(repository_id, token, bucket, opts) do
    case Storage.get(token_bucket_key(repository_id, token, bucket), opts) do
      {:ok, body} ->
        case decode_term(body) do
          {:ok, entries} when is_map(entries) -> entries
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp persist_token_bucket(repository_id, token, bucket, entries, opts) do
    key = token_bucket_key(repository_id, token, bucket)

    if map_size(entries) == 0 do
      case Storage.delete(key, opts) do
        {:ok, _} -> :ok
        {:error, :not_found} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      case Storage.put(key, encode_term(entries), opts) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp count_bucket_entries(entries) do
    Enum.reduce(entries, 0, fn {_path, postings}, acc -> acc + length(postings) end)
  end

  defp candidate_tokens(query) do
    Regex.scan(@token_regex, query)
    |> Enum.map(&hd/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp build_matcher(query, true, case_sensitive?) do
    regex_opts = if case_sensitive?, do: "", else: "i"

    case Regex.compile(query, regex_opts) do
      {:ok, regex} -> {:ok, {:regex, regex}}
      {:error, {reason, at}} -> {:error, {:invalid_regex, "#{reason} at #{at}"}}
    end
  end

  defp build_matcher(query, false, true), do: {:ok, {:plain_case_sensitive, query}}

  defp build_matcher(query, false, false),
    do: {:ok, {:plain_case_insensitive, String.downcase(query)}}

  defp matcher_matches?({:regex, regex}, snippet), do: Regex.match?(regex, snippet)

  defp matcher_matches?({:plain_case_sensitive, query}, snippet),
    do: String.contains?(snippet, query)

  defp matcher_matches?({:plain_case_insensitive, normalized_query}, snippet) do
    String.contains?(String.downcase(snippet), normalized_query)
  end

  defp matcher_column({:regex, regex}, line) do
    case Regex.run(regex, line, return: :index) do
      [{start, _length} | _] -> start + 1
      _ -> nil
    end
  end

  defp matcher_column({:plain_case_sensitive, query}, line) do
    case :binary.match(line, query) do
      {index, _length} -> index + 1
      :nomatch -> nil
    end
  end

  defp matcher_column({:plain_case_insensitive, normalized_query}, line) do
    case :binary.match(String.downcase(line), normalized_query) do
      {index, _length} -> index + 1
      :nomatch -> nil
    end
  end

  defp resolve_revision_hash(repository_id, nil, opts) do
    case Project.get_head(repository_id, opts) do
      {:ok, nil} -> {:ok, Binary.zero_hash()}
      {:ok, head} -> {:ok, head.tree_hash}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_revision_hash(_repository_id, revision_hash, _opts)
       when is_binary(revision_hash) and byte_size(revision_hash) == 32, do: {:ok, revision_hash}

  defp path_matches?(_path, nil, nil), do: true

  defp path_matches?(path, path_prefix, path_glob) do
    prefix_ok =
      case path_prefix do
        nil -> true
        prefix -> String.starts_with?(path, prefix)
      end

    glob_ok =
      case path_glob do
        nil -> true
        glob -> glob_match?(path, glob)
      end

    prefix_ok and glob_ok
  end

  defp glob_match?(path, glob) do
    escaped = Regex.escape(glob)
    pattern = "^" <> String.replace(escaped, "\\*", ".*") <> "$"

    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, path)
      {:error, _} -> false
    end
  end

  defp collapse_changes(changes) do
    changes
    |> Enum.reduce(%{}, fn
      %SessionChange{file_path: file_path} = change, acc
      when is_binary(file_path) and file_path != "" ->
        Map.put(acc, normalize_file_path(file_path), change)

      _change, acc ->
        acc
    end)
    |> Map.values()
  end

  defp load_change_content(%SessionChange{content: content}, _opts) when is_binary(content),
    do: {:ok, content}

  defp load_change_content(%SessionChange{storage_key: key}, opts) when is_binary(key) do
    Storage.get(key, opts)
  end

  defp load_change_content(_change, _opts), do: {:error, :missing_content}

  defp snapshot_tokens(%{tokens: tokens}) when is_map(tokens), do: tokens
  defp snapshot_tokens(_snapshot), do: %{}

  defp snapshot_bucket(%{bucket: bucket}, _path) when is_binary(bucket), do: bucket
  defp snapshot_bucket(_snapshot, path), do: bucket_for_path(path)

  defp get_snapshot_postings(snapshot, token) do
    snapshot
    |> snapshot_tokens()
    |> Map.get(token, [])
  end

  defp normalize_file_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> String.trim_leading("/")
  end

  defp bucket_for_path(path) do
    case path do
      "" ->
        @root_bucket

      _ ->
        path
        |> String.split("/", parts: 2)
        |> hd()
        |> normalize_bucket_segment()
    end
  end

  defp bucket_for_prefix(prefix) do
    prefix
    |> normalize_file_path()
    |> bucket_for_path()
  end

  defp normalize_bucket_segment(""), do: @root_bucket
  defp normalize_bucket_segment(segment), do: URI.encode_www_form(segment)

  defp file_snapshot_key(repository_id, path) do
    Path.join([current_root(repository_id), "files", path <> ".bin"])
  end

  defp token_meta_key(repository_id, token) do
    Path.join([token_root(repository_id, token), "meta.bin"])
  end

  defp token_bucket_key(repository_id, token, bucket) do
    Path.join([token_root(repository_id, token), bucket <> ".bin"])
  end

  defp token_root(repository_id, token) do
    Path.join([
      current_root(repository_id),
      "tokens",
      token_prefix(token),
      token
    ])
  end

  defp token_prefix(token) do
    token
    |> String.slice(0, 2)
    |> String.pad_trailing(2, "_")
  end

  defp current_root(repository_id), do: "repositories/#{repository_id}/index/search/current"
  defp current_meta_key(repository_id), do: Path.join([current_root(repository_id), "meta.bin"])

  defp update_lock_key(repository_id),
    do: Path.join([current_root(repository_id), "updating.lock"])

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 and limit <= 500, do: limit
  defp normalize_limit(_), do: 20

  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_), do: 0

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value != "", do: value
  end

  defp normalize_blank(_), do: nil

  defp landing_metadata_key(repository_id, revision_hash) do
    hash_hex = Base.encode16(revision_hash, case: :lower)
    "repositories/#{repository_id}/index/search/revisions/#{hash_hex}.json"
  end

  defp encode_term(term), do: :erlang.term_to_binary(term, compressed: 9)

  defp decode_term(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_term}
  end

  defp resolve_attributed_to_handle(%{user_id: user_id}) when is_binary(user_id) do
    case Accounts.get_user_with_account(user_id) do
      %{account: %{handle: handle}} when is_binary(handle) and handle != "" -> handle
      _ -> ""
    end
  end

  defp resolve_attributed_to_handle(_), do: ""
end
