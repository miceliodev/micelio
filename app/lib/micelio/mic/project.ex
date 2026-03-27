defmodule Micelio.Mic.Project do
  @moduledoc """
  Read-only access to a repository's current tree and blob contents.

  This is used to render GitHub-like repository views from Mic storage.
  """

  alias Micelio.Mic.{Binary, DeltaCompression, Tree}
  alias Micelio.Storage

  @zero_hash Binary.zero_hash()

  @type entry ::
          %{
            type: :tree | :blob,
            name: String.t(),
            path: String.t()
          }

  @spec get_head(binary(), Keyword.t()) :: {:ok, map() | nil} | {:error, term()}
  def get_head(repository_id, opts \\ []) when is_binary(repository_id) do
    case Storage.get(head_key(repository_id), opts) do
      {:ok, content} ->
        Binary.decode_head(content)

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_tree(binary(), binary(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  def get_tree(repository_id, tree_hash, opts \\ [])
      when is_binary(repository_id) and is_binary(tree_hash) do
    if tree_hash == @zero_hash do
      {:ok, Tree.empty()}
    else
      case Storage.get(tree_key(repository_id, tree_hash), opts) do
        {:ok, content} ->
          case Tree.decode(content) do
            {:ok, tree} -> {:ok, tree}
            {:error, _} -> {:ok, Tree.empty()}
          end

        {:error, :not_found} ->
          {:ok, Tree.empty()}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec get_blob(binary(), binary(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def get_blob(repository_id, blob_hash, opts \\ [])
      when is_binary(repository_id) and is_binary(blob_hash) do
    case Storage.get(blob_key(repository_id, blob_hash), opts) do
      {:ok, content} ->
        DeltaCompression.decode(content, fn hash ->
          Storage.get(blob_key(repository_id, hash), opts)
        end)

      error ->
        error
    end
  end

  @spec blob_hash_for_path(map(), String.t()) :: binary() | nil
  def blob_hash_for_path(tree, file_path) when is_map(tree) and is_binary(file_path) do
    Map.get(tree, file_path)
  end

  @spec directory_exists?(map(), String.t()) :: boolean()
  def directory_exists?(tree, dir_path) when is_map(tree) and is_binary(dir_path) do
    prefix = normalize_prefix(dir_path)
    Enum.any?(tree, fn {path, _hash} -> String.starts_with?(path, prefix) end)
  end

  @spec list_entries(map(), String.t()) :: [entry()]
  def list_entries(tree, dir_path) when is_map(tree) and is_binary(dir_path) do
    prefix = normalize_prefix(dir_path)

    %{dirs: dirs, files: files} =
      Enum.reduce(tree, %{dirs: MapSet.new(), files: []}, fn {path, _hash}, acc ->
        if String.starts_with?(path, prefix) do
          rest = String.replace_prefix(path, prefix, "")

          case String.split(rest, "/", parts: 2) do
            [name] ->
              %{acc | files: [name | acc.files]}

            [dir, _] ->
              %{acc | dirs: MapSet.put(acc.dirs, dir)}

            _ ->
              acc
          end
        else
          acc
        end
      end)

    dir_entries =
      dirs
      |> Enum.map(fn name -> %{type: :tree, name: name, path: join_path(dir_path, name)} end)
      |> Enum.sort_by(& &1.name, :asc)

    file_entries =
      files
      |> Enum.uniq()
      |> Enum.map(fn name -> %{type: :blob, name: name, path: join_path(dir_path, name)} end)
      |> Enum.sort_by(& &1.name, :asc)

    dir_entries ++ file_entries
  end

  @spec head_key(binary()) :: String.t()
  def head_key(repository_id) when is_binary(repository_id),
    do: "repositories/#{repository_id}/head"

  @spec tree_key(binary(), binary()) :: String.t()
  def tree_key(repository_id, tree_hash) when is_binary(repository_id) and is_binary(tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/trees/#{prefix}/#{hash_hex}.bin"
  end

  @spec blob_key(binary(), binary()) :: String.t()
  def blob_key(repository_id, blob_hash) when is_binary(repository_id) and is_binary(blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "repositories/#{repository_id}/blobs/#{prefix}/#{hash_hex}.bin"
  end

  defp normalize_prefix(""), do: ""
  defp normalize_prefix("/"), do: ""

  defp normalize_prefix(dir_path) do
    dir_path = String.trim(dir_path, "/")
    if dir_path == "", do: "", else: dir_path <> "/"
  end

  defp join_path("", name), do: name
  defp join_path(dir_path, name), do: String.trim(dir_path, "/") <> "/" <> name
end
