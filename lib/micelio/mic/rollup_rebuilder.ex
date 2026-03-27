defmodule Micelio.Mic.RollupRebuilder do
  @moduledoc """
  Rebuilds rollup indexes over landing ranges.
  """

  alias Micelio.Mic.{Binary, ConflictIndex}
  alias Micelio.Storage

  require Logger

  def rebuild(repository_id, from_position, to_position, opts \\ [])

  def rebuild(repository_id, from_position, to_position, opts)
      when from_position <= to_position do
    Logger.debug(
      "mic.rollup_rebuild project=#{repository_id} from=#{from_position} to=#{to_position}"
    )

    Enum.each([1, 2, 3], fn level ->
      starts =
        ConflictIndex.rollup_starts(ConflictIndex.rollup_size(level), from_position, to_position)

      Enum.each(starts, fn start_position ->
        _ = ConflictIndex.build_rollup(repository_id, level, start_position, opts)
      end)
    end)

    :ok
  end

  def rebuild(_repository_id, from_position, to_position, _opts)
      when from_position > to_position,
      do: :ok

  def rebuild_from_head(repository_id, from_position \\ 1, opts \\ []) do
    case Storage.get(head_key(repository_id), opts) do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content) do
          rebuild(repository_id, from_position, head.position, opts)
        end

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def head_position(repository_id, opts \\ []) do
    case Storage.get(head_key(repository_id), opts) do
      {:ok, content} ->
        case Binary.decode_head(content) do
          {:ok, head} -> {:ok, head.position}
          {:error, _} -> {:ok, 0}
        end

      {:error, :not_found} ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp head_key(repository_id), do: "repositories/#{repository_id}/head"
end
