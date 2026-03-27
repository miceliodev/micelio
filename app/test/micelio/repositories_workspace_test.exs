defmodule Micelio.RepositoriesWorkspaceTest do
  use Micelio.DataCase, async: true

  alias Micelio.Mic.Project
  alias Micelio.Repositories
  alias Micelio.Storage
  alias Micelio.StorageHelper

  setup do
    {:ok, storage} = StorageHelper.create_isolated_storage()
    # Create source directory for test files
    source_dir = Path.join(storage.base_dir, "source")
    File.mkdir_p!(source_dir)

    on_exit(fn ->
      StorageHelper.cleanup(storage)
    end)

    {:ok, %{source_dir: source_dir, storage_config: storage.config}}
  end

  test "seeds the Micelio workspace from a local path", %{
    source_dir: source_dir,
    storage_config: storage_config
  } do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")
    File.mkdir_p!(Path.join(source_dir, "lib"))
    File.write!(Path.join([source_dir, "lib", "app.ex"]), "IO.puts(\"hi\")\n")

    assert {:ok, %{repository: repository, file_count: 2, tree_hash: tree_hash}} =
             Micelio.Repositories.seed_micelio_workspace(source_dir,
               storage_config: storage_config
             )

    assert repository.handle == "micelio"

    assert {:ok, head} = Project.get_head(repository.id, storage_config: storage_config)
    assert head.position == 1
    assert head.tree_hash == tree_hash

    assert {:ok, tree} =
             Project.get_tree(repository.id, tree_hash, storage_config: storage_config)

    assert Map.has_key?(tree, "README.md")
    assert Map.has_key?(tree, "lib/app.ex")

    readme_hash = Map.fetch!(tree, "README.md")

    assert {:ok, "Micelio workspace\n"} =
             Storage.get(Project.blob_key(repository.id, readme_hash),
               storage_config: storage_config
             )
  end

  test "returns already_seeded on subsequent seed attempts", %{
    source_dir: source_dir,
    storage_config: storage_config
  } do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")

    assert {:ok, %{repository: repository}} =
             Micelio.Repositories.seed_micelio_workspace(source_dir,
               storage_config: storage_config
             )

    assert {:ok, %{repository: same_repository, already_seeded: true}} =
             Micelio.Repositories.seed_micelio_workspace(source_dir,
               storage_config: storage_config
             )

    assert same_repository.id == repository.id
  end

  test "skips configured seed when no path is provided" do
    assert {:ok, :skipped} = Repositories.seed_micelio_workspace_if_configured(path: nil)
  end

  test "seeds configured workspace for a provided project", %{
    source_dir: source_dir,
    storage_config: storage_config
  } do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")

    assert {:ok, %{repository: repository}} = Repositories.ensure_micelio_workspace()

    assert {:ok, %{repository: seeded_repository, file_count: 1}} =
             Micelio.Repositories.seed_micelio_workspace_if_configured(
               path: source_dir,
               project: repository,
               seed_opts: [storage_config: storage_config]
             )

    assert seeded_repository.id == repository.id
  end
end
