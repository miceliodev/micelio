defmodule Micelio.Mic.Repository do
  @moduledoc """
  Compatibility wrapper for repository storage helpers.
  """

  alias Micelio.Mic.Project

  defdelegate get_head(repository_id), to: Project
  defdelegate get_tree(repository_id, tree_hash), to: Project
  defdelegate get_blob(repository_id, blob_hash), to: Project
  defdelegate blob_hash_for_path(tree, file_path), to: Project
  defdelegate directory_exists?(tree, dir_path), to: Project
  defdelegate list_entries(tree, dir_path), to: Project
  defdelegate head_key(repository_id), to: Project
  defdelegate tree_key(repository_id, tree_hash), to: Project
  defdelegate blob_key(repository_id, blob_hash), to: Project
end
