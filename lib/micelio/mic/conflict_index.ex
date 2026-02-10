defmodule Micelio.Mic.ConflictIndex do
  @moduledoc """
  Rollup index for landing conflict filters and path indexes.
  """

  alias Micelio.Mic.Binary
  alias Micelio.Sessions.Conflict
  alias Micelio.Storage

  require Logger

  @rollup_levels [
    %{level: 1, size: 100},
    %{level: 2, size: 10_000},
    %{level: 3, size: 1_000_000}
  ]

  def rollup_size(level) do
    level
    |> rollup_level()
    |> Map.fetch!(:size)
  end

  def maybe_update_rollups(repository_id, position, _change_filter, opts \\ []) do
    advance_rollups(repository_id, position, opts)
  end

  def advance_rollups(repository_id, target_position, opts \\ [])
      when is_integer(target_position) do
    Enum.reduce_while(@rollup_levels, :ok, fn %{level: level, size: size}, _acc ->
      case load_checkpoint(repository_id, level, opts) do
        {:ok, last_built} ->
          from_position = max(1, last_built + 1)
          starts = rollup_starts(size, from_position, target_position)

          Enum.reduce_while(starts, :ok, fn start_position, _ ->
            case build_rollup(repository_id, level, start_position, opts) do
              {:ok, _} -> {:cont, :ok}
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
          |> case do
            {:error, reason} -> {:halt, {:error, reason}}
            _ -> {:cont, :ok}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def expand_ranges(repository_id, from_position, to_position, paths) do
    expand_ranges(repository_id, from_position, to_position, paths, [])
  end

  def expand_ranges(repository_id, from_position, to_position, paths, opts) do
    expand_ranges_with(repository_id, from_position, to_position, paths, fn proj, level, start ->
      load_rollup(proj, level, start, opts)
    end)
  end

  def expand_ranges_with(repository_id, from_position, to_position, paths, load_rollup_fun)
      when is_function(load_rollup_fun, 3) do
    levels = Enum.sort_by(@rollup_levels, & &1.level, :desc)
    do_expand(repository_id, from_position, to_position, paths, levels, load_rollup_fun)
  end

  def load_rollup(repository_id, level, start_position, opts \\ []) do
    case Storage.get(rollup_key(repository_id, level, start_position), opts) do
      {:ok, content} -> Binary.decode_filter_index(content)
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_checkpoint(repository_id, level, opts \\ []) do
    case Storage.get(checkpoint_key(repository_id, level), opts) do
      {:ok, content} ->
        case Binary.decode_rollup_checkpoint(content) do
          {:ok, position} -> {:ok, position}
          {:error, _} -> {:ok, 0}
        end

      {:error, :not_found} ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def store_checkpoint(repository_id, level, position, opts \\ []) do
    encoded = Binary.encode_rollup_checkpoint(position)
    Storage.put(checkpoint_key(repository_id, level), encoded, opts)
  end

  def load_landing_filters(repository_id, from_position, to_position, opts \\ []) do
    entries =
      for position <- from_position..to_position do
        key = landing_key(repository_id, position)

        case Storage.get(key, opts) do
          {:ok, content} ->
            case Binary.decode_landing(content) do
              {:ok, %{session_id: session_id, change_filter: filter}} ->
                {session_id, filter}

              {:error, _} ->
                nil
            end

          {:error, _} ->
            nil
        end
      end

    {:ok, Enum.reject(entries, &is_nil/1)}
  end

  def load_landing_filter(repository_id, position, opts \\ []) do
    case Storage.get(landing_key(repository_id, position), opts) do
      {:ok, content} ->
        case Binary.decode_landing(content) do
          {:ok, %{session_id: session_id, change_filter: filter}} ->
            {:ok, {session_id, filter}}

          {:error, _} ->
            {:ok, nil}
        end

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def store_path_index(repository_id, position, paths, opts \\ []) when is_list(paths) do
    if Enum.empty?(paths) do
      :ok
    else
      encoded = Binary.encode_path_index(paths)

      case Storage.put(path_index_key(repository_id, position), encoded, opts) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    end
  end

  def load_path_index(repository_id, position, opts \\ []) do
    case Storage.get(path_index_key(repository_id, position), opts) do
      {:ok, content} -> Binary.decode_path_index(content)
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def build_rollup(repository_id, level, start_position, opts \\ []) do
    level_spec = rollup_level(level)
    size = level_spec.size
    end_position = start_position + size - 1
    prev_level = level - 1

    Logger.debug(
      "mic.rollup_build level=#{level} start=#{start_position} end=#{end_position} project=#{repository_id}"
    )

    with {:ok, filters} <-
           load_rollup_filters(
             repository_id,
             level,
             prev_level,
             start_position,
             end_position,
             opts
           ) do
      merged = Conflict.merge_filters(filters)

      result =
        if merged do
          encoded = Binary.encode_filter_index(merged)
          Storage.put(rollup_key(repository_id, level, start_position), encoded, opts)
        else
          :ok
        end

      case result do
        {:ok, _} ->
          store_checkpoint(repository_id, level, end_position, opts)

        :ok ->
          store_checkpoint(repository_id, level, end_position, opts)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp landing_key(repository_id, position),
    do: "projects/#{repository_id}/landing/#{pad_position(position)}.bin"

  defp rollup_key(repository_id, level, start_position) do
    "projects/#{repository_id}/landing/bloom/level-#{level}/#{pad_position(start_position)}.bin"
  end

  defp path_index_key(repository_id, position) do
    "projects/#{repository_id}/landing/paths/#{pad_position(position)}.bin"
  end

  defp checkpoint_key(repository_id, level) do
    "projects/#{repository_id}/landing/bloom/checkpoint/level-#{level}.bin"
  end

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp rollup_level(level) do
    Enum.find(@rollup_levels, fn spec -> spec.level == level end)
  end

  defp load_rollup_filters(repository_id, _level, 0, start_position, end_position, opts) do
    with {:ok, entries} <- load_landing_filters(repository_id, start_position, end_position, opts) do
      {:ok, Enum.map(entries, fn {_session_id, filter} -> filter end)}
    end
  end

  defp load_rollup_filters(repository_id, _level, prev_level, start_position, end_position, opts) do
    prev_size = rollup_size(prev_level)

    filters =
      for start_pos <- start_position..end_position//prev_size do
        case load_rollup(repository_id, prev_level, start_pos, opts) do
          {:ok, filter} -> filter
          {:error, _} -> nil
        end
      end

    {:ok, Enum.reject(filters, &is_nil/1)}
  end

  defp do_expand(_repository_id, from_position, to_position, _paths, _levels, _loader)
       when from_position > to_position, do: []

  defp do_expand(_repository_id, from_position, to_position, _paths, [], _loader) do
    [{from_position, to_position}]
  end

  defp do_expand(repository_id, from_position, to_position, paths, [level | rest], loader) do
    size = level.size
    first_start = div(from_position - 1, size) * size + 1
    last_start = div(to_position - 1, size) * size + 1

    Enum.flat_map(first_start..last_start//size, fn start_pos ->
      block_end = start_pos + size - 1
      block_from = max(from_position, start_pos)
      block_to = min(to_position, block_end)

      if block_from == start_pos and block_to == block_end do
        case loader.(repository_id, level.level, start_pos) do
          {:ok, nil} ->
            do_expand(repository_id, block_from, block_to, paths, rest, loader)

          {:ok, filter} ->
            if any_conflicts?(paths, filter) do
              do_expand(repository_id, block_from, block_to, paths, rest, loader)
            else
              []
            end

          {:error, _} ->
            do_expand(repository_id, block_from, block_to, paths, rest, loader)
        end
      else
        do_expand(repository_id, block_from, block_to, paths, rest, loader)
      end
    end)
  end

  defp any_conflicts?(paths, filter) do
    Enum.any?(paths, fn path -> Conflict.might_conflict?(filter, path) end)
  end

  def rollup_starts(level_size, from_position, to_position) do
    if from_position > to_position do
      []
    else
      first_start = div(from_position - 1, level_size) * level_size + 1
      last_start = div(to_position - 1, level_size) * level_size + 1
      Enum.to_list(first_start..last_start//level_size)
    end
  end
end
