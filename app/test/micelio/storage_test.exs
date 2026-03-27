defmodule Micelio.StorageTest do
  use ExUnit.Case, async: true

  alias Micelio.Storage
  alias Micelio.StorageHelper

  describe "backend selection" do
    test "uses local backend when configured" do
      {:ok, storage} = StorageHelper.create_isolated_storage()

      on_exit(fn ->
        StorageHelper.cleanup(storage)
      end)

      key = "test/local.txt"
      content = "local content"
      opts = StorageHelper.storage_opts(storage)

      {:ok, ^key} = Storage.put(key, content, opts)
      {:ok, ^content} = Storage.get(key, opts)

      # Cleanup
      Storage.delete(key, opts)
    end

    test "uses S3 backend when configured" do
      key = "test/s3.txt"
      content = "s3 content"

      config = [
        backend: :s3,
        s3_bucket: "test-bucket",
        s3_region: "us-east-1",
        s3_access_key_id: "test-key",
        s3_secret_access_key: "test-secret",
        req_options: [plug: {Req.Test, Micelio.StorageTest}, retry: false]
      ]

      opts = StorageHelper.storage_opts(config)

      # Expect PUT then GET requests
      Req.Test.expect(Micelio.StorageTest, fn conn ->
        assert conn.method == "PUT"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      Req.Test.expect(Micelio.StorageTest, fn conn ->
        assert conn.method == "GET"
        Plug.Conn.send_resp(conn, 200, content)
      end)

      {:ok, ^key} = Storage.put(key, content, opts)
      {:ok, ^content} = Storage.get(key, opts)
    end

    test "defaults to local backend when not configured" do
      # Create a temp directory for this test
      unique = System.unique_integer([:positive])
      tmp_dir = Path.join(System.tmp_dir!(), "micelio-default-test-#{unique}")

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      # The default local backend uses a temp directory
      key = "test/default.txt"
      content = "default content"
      opts = StorageHelper.storage_opts(backend: :local, local_path: tmp_dir)

      {:ok, ^key} = Storage.put(key, content, opts)
      {:ok, ^content} = Storage.get(key, opts)

      # Cleanup
      Storage.delete(key, opts)
    end

    test "uses tiered backend when configured" do
      unique = Integer.to_string(:erlang.unique_integer([:positive]))
      origin_dir = Path.join(System.tmp_dir!(), "micelio-test-origin-#{unique}")
      cache_dir = Path.join(System.tmp_dir!(), "micelio-test-cache-#{unique}")

      on_exit(fn ->
        File.rm_rf(origin_dir)
        File.rm_rf(cache_dir)
      end)

      config = [
        backend: :tiered,
        origin_backend: :local,
        origin_local_path: origin_dir,
        cache_disk_path: cache_dir,
        cache_memory_max_bytes: 1_000_000,
        cache_namespace: "storage-test-#{unique}"
      ]

      opts = StorageHelper.storage_opts(config)

      key = "test/tiered.txt"
      content = "tiered content"

      {:ok, ^key} = Storage.put(key, content, opts)
      {:ok, ^content} = Storage.get(key, opts)
      assert File.exists?(Path.join(cache_dir, key))
    end
  end

  describe "cdn_url/1" do
    test "returns a CDN URL when configured" do
      config = [cdn_base_url: "https://cdn.example.test/micelio"]
      opts = StorageHelper.storage_opts(config)

      key = "projects/123/blobs/aa/file name.txt"

      assert Storage.cdn_url(key, opts) ==
               "https://cdn.example.test/micelio/projects/123/blobs/aa/file%20name.txt"
    end

    test "returns nil when CDN is not configured" do
      assert Storage.cdn_url("projects/123/blobs/aa/file.txt", storage_config: []) == nil
    end
  end
end
