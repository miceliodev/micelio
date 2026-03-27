defmodule Micelio.Mic.SeedTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Mic.{Project, Seed}
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

  test "seeds repository storage from a local path", %{
    source_dir: source_dir,
    storage_config: storage_config
  } do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "seed-org-#{unique}",
        name: "Seed Org #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "seed-proj-#{unique}",
        name: "Seed Project #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    File.write!(Path.join(source_dir, "README.md"), "Hello world\n")
    File.mkdir_p!(Path.join(source_dir, "lib"))
    File.write!(Path.join([source_dir, "lib", "app.ex"]), "IO.puts(\"hi\")\n")

    assert {:ok, %{file_count: 2, tree_hash: tree_hash}} =
             Seed.seed_repository_from_path(repository.id, source_dir,
               storage_config: storage_config
             )

    assert {:ok, head} = Project.get_head(repository.id, storage_config: storage_config)
    assert head.position == 1
    assert head.tree_hash == tree_hash

    assert {:ok, tree} =
             Project.get_tree(repository.id, tree_hash, storage_config: storage_config)

    assert Map.has_key?(tree, "README.md")
    assert Map.has_key?(tree, "lib/app.ex")

    readme_hash = Map.fetch!(tree, "README.md")

    assert {:ok, "Hello world\n"} =
             Storage.get(Project.blob_key(repository.id, readme_hash),
               storage_config: storage_config
             )
  end

  test "returns already_seeded when head exists", %{
    source_dir: source_dir,
    storage_config: storage_config
  } do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "seed-org-repeat-#{unique}",
        name: "Seed Org Repeat #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "seed-proj-repeat-#{unique}",
        name: "Seed Project Repeat #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    File.write!(Path.join(source_dir, "README.md"), "Hello again\n")

    assert {:ok, _} =
             Seed.seed_repository_from_path(repository.id, source_dir,
               storage_config: storage_config
             )

    assert {:error, :already_seeded} =
             Seed.seed_repository_from_path(repository.id, source_dir,
               storage_config: storage_config
             )
  end
end
