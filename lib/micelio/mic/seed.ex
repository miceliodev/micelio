defmodule Micelio.Mic.Seed do
  @moduledoc """
  Seeds repository storage from a local workspace checkout.
  """

  alias Micelio.Mic.{Binary, Project, Tree}
  alias Micelio.Storage

  @default_ignore [".git", ".mic", "_build", "deps", "tmp", "node_modules"]

  @spec seed_repository_from_path(binary(), binary(), keyword()) ::
          {:ok, %{file_count: non_neg_integer(), tree_hash: binary()}}
          | {:error, term()}
  def seed_repository_from_path(repository_id, root_path, opts \\ [])
      when is_binary(repository_id) and is_binary(root_path) do
    ignore = MapSet.new(@default_ignore ++ Keyword.get(opts, :ignore, []))
    position = Keyword.get(opts, :position, 1)

    with :ok <- ensure_head_missing(repository_id, opts),
         {:ok, files} <- list_files(root_path, ignore),
         {:ok, tree} <- store_files(repository_id, root_path, files, opts),
         {:ok, tree_hash} <- store_tree(repository_id, tree, opts),
         {:ok, _} <- store_head(repository_id, position, tree_hash, opts) do
      {:ok, %{file_count: length(files), tree_hash: tree_hash}}
    end
  end

  @spec store_tree_from_path(binary(), binary(), keyword()) ::
          {:ok, %{file_count: non_neg_integer(), tree_hash: binary()}}
          | {:error, term()}
  def store_tree_from_path(repository_id, root_path, opts \\ [])
      when is_binary(repository_id) and is_binary(root_path) do
    ignore = MapSet.new(@default_ignore ++ Keyword.get(opts, :ignore, []))

    with {:ok, files} <- list_files(root_path, ignore),
         {:ok, tree} <- store_files(repository_id, root_path, files, opts),
         {:ok, tree_hash} <- store_tree(repository_id, tree, opts) do
      {:ok, %{file_count: length(files), tree_hash: tree_hash}}
    end
  end

  defp ensure_head_missing(repository_id, opts) do
    case Storage.get(Project.head_key(repository_id), opts) do
      {:ok, _} -> {:error, :already_seeded}
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_files(root_path, ignore) do
    root_path = Path.expand(root_path)

    if File.dir?(root_path) do
      files =
        [root_path, "**", "*"]
        |> Path.join()
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, root_path))
        |> Enum.reject(&ignore_path?(&1, ignore))
        |> Enum.sort()

      {:ok, files}
    else
      {:error, :invalid_path}
    end
  end

  defp ignore_path?(relative_path, ignore) do
    relative_path
    |> Path.split()
    |> Enum.any?(&MapSet.member?(ignore, &1))
  end

  defp store_files(repository_id, root_path, files, opts) do
    Enum.reduce_while(files, {:ok, %{}}, fn relative_path, {:ok, acc} ->
      full_path = Path.join(root_path, relative_path)

      case File.read(full_path) do
        {:ok, content} ->
          blob_hash = :crypto.hash(:sha256, content)

          case Storage.put_if_none_match(
                 Project.blob_key(repository_id, blob_hash),
                 content,
                 opts
               ) do
            {:ok, _} ->
              {:cont, {:ok, Map.put(acc, relative_path, blob_hash)}}

            {:error, :precondition_failed} ->
              {:cont, {:ok, Map.put(acc, relative_path, blob_hash)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp store_tree(repository_id, tree, opts) do
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)

    case Storage.put_if_none_match(Project.tree_key(repository_id, tree_hash), encoded_tree, opts) do
      {:ok, _} -> {:ok, tree_hash}
      {:error, :precondition_failed} -> {:ok, tree_hash}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_head(repository_id, position, tree_hash, opts) do
    head_binary = Binary.encode_head(Binary.new_head(position, tree_hash))

    case Storage.put_if_none_match(Project.head_key(repository_id), head_binary, opts) do
      {:ok, _} -> {:ok, position}
      {:error, :precondition_failed} -> {:error, :already_seeded}
      {:error, reason} -> {:error, reason}
    end
  end
end
