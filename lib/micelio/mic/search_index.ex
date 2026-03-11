defmodule Micelio.Mic.SearchIndex do
  @moduledoc """
  Repository-scoped text search index used by `hif.v1.SearchService`.

  The index is append-only per token and revision hash. Query-time filtering handles
  path/revision constraints and deduplicates to the latest revision snapshot.
  """

  alias Micelio.Accounts
  alias Micelio.Mic.Binary
  alias Micelio.Mic.Project
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  @token_regex ~r/[A-Za-z0-9_]{2,}/u
  @zero_hash Binary.zero_hash()

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

    postings_by_token =
      changes
      |> Enum.reduce(%{}, fn change, acc ->
        accumulate_change_postings(
          acc,
          change,
          session.session_id,
          attributed_to_handle,
          revision_hash,
          landed_at_ms,
          opts
        )
      end)

    with :ok <-
           Enum.reduce_while(postings_by_token, :ok, fn {token, new_postings}, :ok ->
             case append_token_postings(repository_id, token, new_postings, opts) do
               :ok -> {:cont, :ok}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
      update_index_metadata(repository_id, revision_hash, opts)
    end
  end

  @spec query(binary(), map(), keyword()) ::
          {:ok,
           %{total: non_neg_integer(), matches: [posting()], next_offset: non_neg_integer() | nil}}
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
         :ok <- ensure_index_fresh(repository_id, query_revision_hash, opts),
         {:ok, visible_paths} <- load_visible_paths(repository_id, query_revision_hash, opts) do
      cutoff_ms = landing_cutoff_ms(repository_id, query_revision_hash, opts)

      postings =
        query
        |> load_candidate_postings(repository_id, opts)
        |> Enum.filter(&within_cutoff?(&1, cutoff_ms))
        |> Enum.filter(&visible?(visible_paths, &1.path))
        |> Enum.filter(&path_matches?(&1.path, path_prefix, path_glob))
        |> Enum.filter(&query_matches?(&1, query, regex?, case_sensitive?))
        |> latest_per_line()
        |> Enum.sort_by(fn posting ->
          {-posting.landed_at_ms, posting.path, posting.line, posting.column}
        end)

      total = length(postings)
      matches = postings |> Enum.drop(offset) |> Enum.take(limit)
      next_offset = if offset + limit < total, do: offset + limit

      {:ok, %{total: total, matches: matches, next_offset: next_offset}}
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

  defp accumulate_change_postings(
         acc,
         %SessionChange{change_type: type},
         _session_id,
         _attributed_to_handle,
         _revision_hash,
         _landed_at_ms,
         _opts
       )
       when type in ["deleted", "renamed"], do: acc

  defp accumulate_change_postings(
         acc,
         %SessionChange{} = change,
         session_id,
         attributed_to_handle,
         revision_hash,
         landed_at_ms,
         opts
       ) do
    case load_change_content(change, opts) do
      {:ok, content} ->
        build_postings(
          change.file_path,
          content,
          session_id,
          attributed_to_handle,
          revision_hash,
          landed_at_ms
        )
        |> Enum.reduce(acc, fn {token, posting}, token_acc ->
          Map.update(token_acc, token, [posting], fn existing -> [posting | existing] end)
        end)

      _ ->
        acc
    end
  end

  defp build_postings(
         path,
         content,
         session_id,
         attributed_to_handle,
         revision_hash,
         landed_at_ms
       )
       when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      Regex.scan(@token_regex, line, return: :index)
      |> Enum.map(fn [{column, length}] ->
        token = String.slice(line, column, length) |> String.downcase()

        posting = %{
          path: path,
          line: line_number,
          column: column + 1,
          snippet: String.slice(line, 0, 400),
          session_id: session_id,
          attributed_to_handle: attributed_to_handle,
          revision_hash: revision_hash,
          landed_at_ms: landed_at_ms
        }

        {token, posting}
      end)
    end)
  end

  defp load_change_content(%SessionChange{content: content}, _opts) when is_binary(content),
    do: {:ok, content}

  defp load_change_content(%SessionChange{storage_key: key}, opts) when is_binary(key) do
    Storage.get(key, opts)
  end

  defp load_change_content(_change, _opts), do: {:error, :missing_content}

  defp append_token_postings(repository_id, token, new_postings, opts) do
    key = token_key(repository_id, token)

    existing =
      case Storage.get(key, opts) do
        {:ok, body} -> Jason.decode!(body)
        {:error, :not_found} -> []
        {:error, _} -> []
      end

    payload = Jason.encode!(existing ++ Enum.map(new_postings, &stringify_posting/1))

    case Storage.put(key, payload, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_key(repository_id, token) do
    "repositories/#{repository_id}/index/search/tokens/#{token}.json"
  end

  defp metadata_key(repository_id) do
    "repositories/#{repository_id}/index/search/meta.json"
  end

  defp update_index_metadata(repository_id, revision_hash, opts) do
    payload =
      Jason.encode!(%{
        "indexed_revision_hash" => Base.encode16(revision_hash, case: :lower),
        "updated_at_ms" => System.system_time(:millisecond)
      })

    case Storage.put(metadata_key(repository_id), payload, opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_index_revision_hash(repository_id, opts) do
    case Storage.get(metadata_key(repository_id), opts) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"indexed_revision_hash" => value}} when is_binary(value) ->
            decode_revision_hash(value)

          _ ->
            Binary.zero_hash()
        end

      _ ->
        Binary.zero_hash()
    end
  end

  defp load_candidate_postings(query, repository_id, opts) do
    tokens =
      Regex.scan(@token_regex, query)
      |> Enum.map(&hd/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    Enum.flat_map(tokens, fn token ->
      case Storage.get(token_key(repository_id, token), opts) do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, list} when is_list(list) -> Enum.map(list, &normalize_posting/1)
            _ -> []
          end

        _ ->
          []
      end
    end)
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

  defp load_visible_paths(_repository_id, revision_hash, _opts)
       when is_binary(revision_hash) and revision_hash == @zero_hash, do: {:ok, MapSet.new()}

  defp load_visible_paths(repository_id, revision_hash, opts) do
    with {:ok, tree} <- Project.get_tree(repository_id, revision_hash, opts) do
      {:ok, MapSet.new(Map.keys(tree))}
    end
  end

  defp visible?(paths, path) do
    MapSet.size(paths) == 0 or MapSet.member?(paths, path)
  end

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

  defp query_matches?(posting, query, true, case_sensitive?) do
    regex_opts = if case_sensitive?, do: "", else: "i"

    case Regex.compile(query, regex_opts) do
      {:ok, regex} -> Regex.match?(regex, posting.snippet)
      {:error, _} -> false
    end
  end

  defp query_matches?(posting, query, false, true), do: String.contains?(posting.snippet, query)

  defp query_matches?(posting, query, false, false) do
    String.contains?(String.downcase(posting.snippet), String.downcase(query))
  end

  defp latest_per_line(postings) do
    postings
    |> Enum.group_by(fn p -> {p.path, p.line, p.column} end)
    |> Enum.map(fn {_key, group} -> Enum.max_by(group, & &1.landed_at_ms) end)
  end

  defp glob_match?(path, glob) do
    # Minimal glob support: `*` matches zero or more chars.
    escaped = Regex.escape(glob)
    pattern = "^" <> String.replace(escaped, "\\*", ".*") <> "$"

    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, path)
      {:error, _} -> false
    end
  end

  defp normalize_posting(%{} = value) do
    %{
      path: Map.get(value, "path", ""),
      line: Map.get(value, "line", 0),
      column: Map.get(value, "column", 0),
      snippet: Map.get(value, "snippet", ""),
      session_id: Map.get(value, "session_id", ""),
      attributed_to_handle:
        Map.get(value, "attributed_to_handle", Map.get(value, "author_handle", "")),
      revision_hash: Map.get(value, "revision_hash", "") |> decode_revision_hash(),
      landed_at_ms: Map.get(value, "landed_at_ms", 0)
    }
  end

  defp stringify_posting(%{} = value) do
    %{
      "path" => value.path,
      "line" => value.line,
      "column" => value.column,
      "snippet" => value.snippet,
      "session_id" => value.session_id,
      "attributed_to_handle" => value.attributed_to_handle,
      "revision_hash" => Base.encode16(value.revision_hash, case: :lower),
      "landed_at_ms" => value.landed_at_ms
    }
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 and limit <= 500, do: limit
  defp normalize_limit(_), do: 20

  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_), do: 0

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value != "", do: value
  end

  defp normalize_blank(_), do: nil

  defp within_cutoff?(posting, cutoff_ms) when is_integer(cutoff_ms) and cutoff_ms > 0 do
    posting.landed_at_ms <= cutoff_ms
  end

  defp within_cutoff?(_posting, _cutoff_ms), do: true

  defp landing_cutoff_ms(_repository_id, revision_hash, _opts)
       when is_binary(revision_hash) and revision_hash == @zero_hash, do: 0

  defp landing_cutoff_ms(repository_id, revision_hash, opts) do
    case Storage.get(landing_metadata_key(repository_id, revision_hash), opts) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"landed_at_ms" => value}} when is_integer(value) -> value
          {:ok, %{"landed_at_ms" => value}} when is_binary(value) -> parse_ms(value)
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp landing_metadata_key(repository_id, revision_hash) do
    hash_hex = Base.encode16(revision_hash, case: :lower)
    "repositories/#{repository_id}/index/search/revisions/#{hash_hex}.json"
  end

  defp parse_ms(value) when is_integer(value), do: value

  defp parse_ms(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp parse_ms(_), do: 0

  defp decode_revision_hash(value) when is_binary(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, decoded} when byte_size(decoded) == 32 -> decoded
      _ -> Binary.zero_hash()
    end
  end

  defp decode_revision_hash(_), do: Binary.zero_hash()

  defp resolve_attributed_to_handle(%{user_id: user_id}) when is_binary(user_id) do
    case Accounts.get_user_with_account(user_id) do
      %{account: %{handle: handle}} when is_binary(handle) and handle != "" -> handle
      _ -> ""
    end
  end

  defp resolve_attributed_to_handle(_), do: ""
end
