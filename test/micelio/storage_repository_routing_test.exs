defmodule Micelio.StorageRepositoryRoutingTest do
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.Repositories
  alias Micelio.Storage

  defp unique_handle(prefix) do
    unique = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{unique}"
  end

  defp create_organization! do
    {:ok, organization} =
      Accounts.create_organization(%{
        handle: unique_handle("storage-repo"),
        name: "Storage Repo Test"
      })

    organization
  end

  describe "repository-specific storage routing" do
    setup do
      original_storage_config = Application.get_env(:micelio, Micelio.Storage, [])
      unique = Integer.to_string(:erlang.unique_integer([:positive]))
      global_dir = Path.join(System.tmp_dir!(), "micelio-storage-routing-global-#{unique}")
      local_dir = Path.join(System.tmp_dir!(), "micelio-storage-routing-local-#{unique}")
      organization = create_organization!()

      on_exit(fn ->
        Application.put_env(:micelio, Micelio.Storage, original_storage_config)
        File.rm_rf(global_dir)
        File.rm_rf(local_dir)
      end)

      {:ok, organization: organization, global_dir: global_dir, local_dir: local_dir}
    end

    test "applies repository key prefix when storage_key_prefix is set", %{
      organization: organization,
      local_dir: local_dir
    } do
      Application.put_env(:micelio, Micelio.Storage,
        backend: :local,
        local_path: local_dir
      )

      {:ok, repository} =
        Repositories.create_repository(%{
          organization_id: organization.id,
          handle: unique_handle("repo"),
          name: "Prefix Storage",
          visibility: "private",
          storage_key_prefix: "tenant-a",
          storage_backend: "local"
        })

      key = "projects/#{repository.id}/head"
      content = "seed data"

      scoped_key = Path.join("tenant-a", key)
      assert {:ok, ^scoped_key} = Storage.put(key, content)

      expected_path =
        Path.join(local_dir, Path.join(["tenant-a", key]))

      assert File.regular?(expected_path)
    end

    test "respects repository backend override over app-level storage config", %{
      organization: organization,
      global_dir: global_dir
    } do
      Application.put_env(:micelio, Micelio.Storage,
        backend: :s3,
        s3_bucket: "test-bucket",
        s3_region: "us-east-1",
        s3_access_key_id: "test-key",
        s3_secret_access_key: "test-secret",
        req_options: [plug: {Req.Test, Micelio.StorageRepositoryRoutingTest}, retry: false],
        local_path: global_dir
      )

      {:ok, repository} =
        Repositories.create_repository(%{
          organization_id: organization.id,
          handle: unique_handle("repo"),
          name: "Backend Override",
          visibility: "private",
          storage_backend: "local",
          storage_key_prefix: "backend-local"
        })

      Req.Test.expect(Micelio.StorageRepositoryRoutingTest, fn _conn ->
        flunk("expected local storage backend, but S3 request was attempted")
      end)

      key = "projects/#{repository.id}/head"
      content = "local override"

      scoped_key = Path.join("backend-local", key)
      assert {:ok, ^scoped_key} = Storage.put(key, content)

      expected_path = Path.join(global_dir, scoped_key)
      assert File.regular?(expected_path)
    end
  end
end
