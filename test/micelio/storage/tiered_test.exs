defmodule Micelio.Storage.TieredTest do
  use ExUnit.Case, async: true

  alias Micelio.Storage.FakeOrigin
  alias Micelio.Storage.Local
  alias Micelio.Storage.Tiered

  setup do
    unique = Integer.to_string(:erlang.unique_integer([:positive]))
    origin_dir = Path.join(System.tmp_dir!(), "micelio-test-origin-#{unique}")
    cache_dir = Path.join(System.tmp_dir!(), "micelio-test-cache-#{unique}")

    config = [
      origin_backend: :local,
      origin_local_path: origin_dir,
      cache_disk_path: cache_dir,
      cache_memory_max_bytes: 1_000_000,
      cache_namespace: unique
    ]

    on_exit(fn ->
      File.rm_rf(origin_dir)
      File.rm_rf(cache_dir)
    end)

    {:ok, config: config, origin_dir: origin_dir, cache_dir: cache_dir}
  end

  test "reads from origin and seeds disk cache", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/main.ex"
    content = "hello"

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    assert {:ok, ^content} = Tiered.get(key, config)
    assert File.exists?(Path.join(cache_dir, key))
  end

  test "head uses cached metadata after get when origin is missing", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/head.ex"
    content = "head metadata"
    size = byte_size(content)

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-head")

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, ^content} = Tiered.get(key, disk_config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)

    assert {:ok, %{etag: etag, size: ^size}} = Tiered.head(key, disk_config)
    assert is_binary(etag)
  end

  test "reads from disk when memory is empty and origin is missing", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: _cache_dir
  } do
    key = "sessions/abc/files/disk.ex"
    content = "disk cache"

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    assert {:ok, ^content} = Tiered.get(key, config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)

    new_config = Keyword.put(config, :cache_namespace, "#{config[:cache_namespace]}-disk")
    assert {:ok, ^content} = Tiered.get(key, new_config)
  end

  test "reads from configured origin backend module and seeds disk cache", %{
    config: config,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/fake-origin.ex"
    content = "fake origin"

    {:ok, ^key} = FakeOrigin.put(key, content)

    disk_config =
      config
      |> Keyword.put(:origin_backend, FakeOrigin)
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-fake-origin")

    assert {:ok, ^content} = Tiered.get(key, disk_config)
    assert File.exists?(Path.join(cache_dir, key))

    {:ok, ^key} = FakeOrigin.delete(key)
    assert {:ok, ^content} = Tiered.get(key, disk_config)
  end

  test "serves from memory when disk and origin are missing", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/memory.ex"
    content = "memory cache"

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    assert {:ok, ^content} = Tiered.get(key, config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)
    _ = File.rm(Path.join(cache_dir, key))

    assert {:ok, ^content} = Tiered.get(key, config)
  end

  test "get_with_metadata returns origin etag and caches metadata in memory", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/meta.ex"
    content = "metadata"

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, config)

    {:ok, ^key} = Local.delete(key, base_path: origin_dir)
    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, config)
  end

  test "get_with_metadata reads from disk cache when memory is disabled", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/meta-disk.ex"
    content = "disk metadata"

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-disk-meta")

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, disk_config)

    {:ok, ^key} = Local.delete(key, base_path: origin_dir)
    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, disk_config)
  end

  test "reads from CDN when caches miss and seeds disk cache", %{
    config: config,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/cdn.ex"
    content = "cdn content"

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/#{key}"
      Plug.Conn.send_resp(conn, 200, content)
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:cache_memory_max_bytes, 1_000_000)
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert {:ok, ^content} = Tiered.get(key, config)
    assert File.exists?(Path.join(cache_dir, key))

    _ = File.rm(Path.join(cache_dir, key))
    assert {:ok, ^content} = Tiered.get(key, config)
  end

  test "head uses cached CDN metadata after get", %{config: config} do
    key = "sessions/abc/files/cdn-head-cache.ex"
    content = "cdn cached content"
    etag = "cdn-cached-etag"
    size = byte_size(content)

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", etag)
      |> Plug.Conn.send_resp(200, content)
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert {:ok, ^content} = Tiered.get(key, config)
    assert {:ok, %{etag: ^etag, size: ^size}} = Tiered.head(key, config)
  end

  test "falls back to origin when CDN misses and seeds disk cache", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/cdn-miss.ex"
    content = "origin content"

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      Plug.Conn.send_resp(conn, 404, "")
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert {:ok, ^content} = Tiered.get(key, config)
    assert File.exists?(Path.join(cache_dir, key))
  end

  test "exists? checks CDN when caches and origin miss", %{config: config} do
    key = "sessions/abc/files/cdn-exists.ex"

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      assert conn.method == "HEAD"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert Tiered.exists?(key, config)
  end

  test "get_with_metadata reads from CDN and caches metadata", %{
    config: config,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/cdn-meta.ex"
    content = "cdn metadata content"
    etag = "cdn-etag"

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", etag)
      |> Plug.Conn.send_resp(200, content)
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, config)
    assert File.exists?(Path.join(cache_dir, key))
    assert File.exists?(Path.join(cache_dir, "#{key}.meta"))

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-cdn-meta")

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, disk_config)
  end

  test "head reads metadata from memory cache without origin", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/head-memory.ex"
    content = "head memory content"
    size = byte_size(content)

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, config)

    {:ok, ^key} = Local.delete(key, base_path: origin_dir)
    _ = File.rm(Path.join(cache_dir, key))
    _ = File.rm(Path.join(cache_dir, "#{key}.meta"))

    assert {:ok, %{etag: ^etag, size: ^size}} = Tiered.head(key, config)
  end

  test "head reads metadata from disk cache when memory is disabled", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/head-disk.ex"
    content = "head disk content"
    size = byte_size(content)

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-head-disk")

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    assert {:ok, %{content: ^content, etag: ^etag}} = Tiered.get_with_metadata(key, disk_config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)

    assert {:ok, %{etag: ^etag, size: ^size}} = Tiered.head(key, disk_config)
  end

  test "head reads metadata from CDN and seeds caches", %{
    config: config,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/head-cdn.ex"
    content = "cdn head content"
    size = byte_size(content)
    etag = "cdn-head-etag"

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", etag)
      |> Plug.Conn.send_resp(200, content)
    end)

    config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    assert {:ok, %{etag: ^etag, size: ^size}} = Tiered.head(key, config)
    assert File.exists?(Path.join(cache_dir, key))
    assert File.exists?(Path.join(cache_dir, "#{key}.meta"))
  end

  test "head falls back to origin when CDN misses and caches are disabled", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/head-origin.ex"
    content = "origin head content"
    size = byte_size(content)

    head_config =
      config
      |> Keyword.put(:cdn_base_url, "https://cdn.example")
      |> Keyword.put(:cache_disk_path, nil)
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-head-origin")
      |> Keyword.put(:req_options, plug: {Req.Test, Micelio.Storage.TieredTest}, retry: false)

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    Req.Test.stub(Micelio.Storage.TieredTest, fn conn ->
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert {:ok, %{etag: ^etag, size: ^size}} = Tiered.head(key, head_config)
  end

  test "evicts oldest memory entries when cache exceeds limit", %{
    config: config,
    origin_dir: origin_dir
  } do
    key1 = "sessions/abc/files/evict-1.ex"
    key2 = "sessions/abc/files/evict-2.ex"
    content1 = "123456"
    content2 = "abcdef"

    config =
      config
      |> Keyword.put(:cache_disk_path, nil)
      |> Keyword.put(:cache_memory_max_bytes, 10)

    {:ok, ^key1} = Tiered.put(key1, content1, config)
    {:ok, ^key1} = Local.delete(key1, base_path: origin_dir)
    {:ok, ^key2} = Tiered.put(key2, content2, config)

    assert {:error, :not_found} = Tiered.get(key1, config)
    assert {:ok, ^content2} = Tiered.get(key2, config)
  end

  test "put_if_none_match does not seed cache on precondition failure", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/precondition.ex"
    original = "original content"
    updated = "new content"

    {:ok, ^key} = Local.put(key, original, base_path: origin_dir)
    assert {:error, :precondition_failed} = Tiered.put_if_none_match(key, updated, config)
    refute File.exists?(Path.join(cache_dir, key))
  end

  test "put_if_match does not seed cache on precondition failure", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/precondition-match.ex"
    original = "match original"
    updated = "match updated"

    {:ok, ^key} = Local.put(key, original, base_path: origin_dir)

    assert {:error, :precondition_failed} =
             Tiered.put_if_match(key, updated, "wrong-etag", config)

    refute File.exists?(Path.join(cache_dir, key))
  end

  test "put_if_match seeds disk cache on success", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/precondition-success.ex"
    original = "original content"
    updated = "updated content"

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-precondition-success")

    {:ok, ^key} = Local.put(key, original, base_path: origin_dir)
    {:ok, %{etag: etag}} = Local.get_with_metadata(key, base_path: origin_dir)

    assert {:ok, ^key} = Tiered.put_if_match(key, updated, etag, disk_config)
    assert File.exists?(Path.join(cache_dir, key))

    {:ok, ^key} = Local.delete(key, base_path: origin_dir)
    assert {:ok, ^updated} = Tiered.get(key, disk_config)
  end

  test "delete clears disk cache entries and metadata", %{
    config: config,
    origin_dir: origin_dir,
    cache_dir: cache_dir
  } do
    key = "sessions/abc/files/delete-disk.ex"
    content = "delete disk cache"

    disk_config =
      config
      |> Keyword.put(:cache_memory_max_bytes, 0)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-delete-disk")

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    assert {:ok, %{content: ^content}} = Tiered.get_with_metadata(key, disk_config)
    assert File.exists?(Path.join(cache_dir, key))
    assert File.exists?(Path.join(cache_dir, "#{key}.meta"))

    assert {:ok, ^key} = Tiered.delete(key, disk_config)

    refute File.exists?(Path.join(cache_dir, key))
    refute File.exists?(Path.join(cache_dir, "#{key}.meta"))
    refute Local.exists?(key, base_path: origin_dir)
  end

  test "delete clears memory cache entries", %{config: config, origin_dir: origin_dir} do
    key = "sessions/abc/files/delete-cache.ex"
    content = "delete cache"

    memory_config =
      config
      |> Keyword.put(:cache_disk_path, nil)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-delete")

    {:ok, ^key} = Tiered.put(key, content, memory_config)
    assert {:ok, ^key} = Tiered.delete(key, memory_config)

    assert {:error, :not_found} = Tiered.get(key, memory_config)
    refute Local.exists?(key, base_path: origin_dir)
  end

  test "overwriting a key does not evict the latest entry", %{
    config: config,
    origin_dir: origin_dir
  } do
    key = "sessions/abc/files/overwrite-cache.ex"
    content1 = "first"
    content2 = "secon"

    memory_config =
      config
      |> Keyword.put(:cache_disk_path, nil)
      |> Keyword.put(:cache_memory_max_bytes, byte_size(content1))
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-overwrite")

    {:ok, ^key} = Tiered.put(key, content1, memory_config)
    {:ok, ^key} = Tiered.put(key, content2, memory_config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)

    assert {:ok, ^content2} = Tiered.get(key, memory_config)
  end

  test "memory caches are isolated by namespace", %{config: config, origin_dir: origin_dir} do
    key = "sessions/abc/files/namespace-cache.ex"
    content = "namespaced"

    memory_config =
      config
      |> Keyword.put(:cache_disk_path, nil)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-ns1")

    other_config = Keyword.put(memory_config, :cache_namespace, "#{config[:cache_namespace]}-ns2")

    {:ok, ^key} = Local.put(key, content, base_path: origin_dir)
    assert {:ok, ^content} = Tiered.get(key, memory_config)
    {:ok, ^key} = Local.delete(key, base_path: origin_dir)

    assert {:error, :not_found} = Tiered.get(key, other_config)
  end

  test "list delegates to the origin backend", %{config: config} do
    key1 = "sessions/abc/files/list-1.ex"
    key2 = "sessions/abc/files/list-2.ex"

    {:ok, ^key1} = FakeOrigin.put(key1, "list one")
    {:ok, ^key2} = FakeOrigin.put(key2, "list two")

    list_config =
      config
      |> Keyword.put(:origin_backend, FakeOrigin)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-list")

    assert {:ok, keys} = Tiered.list("sessions/abc/files", list_config)
    assert Enum.sort(keys) == Enum.sort([key1, key2])
  end

  test "exists? returns true when cached even if origin is missing", %{config: config} do
    key = "sessions/abc/files/cache-exists.ex"

    {:ok, ^key} = FakeOrigin.put(key, "cached")

    exists_config =
      config
      |> Keyword.put(:origin_backend, FakeOrigin)
      |> Keyword.put(:cache_namespace, "#{config[:cache_namespace]}-exists")

    assert {:ok, ^key} = Tiered.put(key, "cached", exists_config)
    {:ok, ^key} = FakeOrigin.delete(key)

    assert Tiered.exists?(key, exists_config)
  end
end
