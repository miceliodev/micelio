defmodule Micelio.Mic.DeltaCompressionTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.DeltaCompression
  alias Micelio.Mic.Project
  alias Micelio.Storage
  alias Micelio.StorageHelper

  test "encodes delta payloads and reconstructs content" do
    base = String.duplicate("a", 500) <> "b" <> String.duplicate("a", 500)
    content = String.duplicate("a", 500) <> "c" <> String.duplicate("a", 500)
    base_hash = :crypto.hash(:sha256, base)

    assert {:ok, payload} = DeltaCompression.maybe_encode(base_hash, base, content)
    assert byte_size(payload) < byte_size(content)

    fetch = fn
      ^base_hash -> {:ok, base}
      _ -> {:error, :not_found}
    end

    assert {:ok, ^content} = DeltaCompression.decode(payload, fetch)
  end

  test "skips delta encoding when payload is larger than content" do
    base = "short"
    content = "completely different"
    base_hash = :crypto.hash(:sha256, base)

    assert :no_delta = DeltaCompression.maybe_encode(base_hash, base, content)
  end

  test "project get_blob decodes stored delta payloads" do
    {:ok, storage} = StorageHelper.create_isolated_storage()
    opts = StorageHelper.storage_opts(storage)

    on_exit(fn ->
      StorageHelper.cleanup(storage)
    end)

    repository_id = "proj-123"
    base = String.duplicate("x", 200) <> "y" <> String.duplicate("x", 200)
    content = String.duplicate("x", 200) <> "z" <> String.duplicate("x", 200)
    base_hash = :crypto.hash(:sha256, base)
    new_hash = :crypto.hash(:sha256, content)

    assert {:ok, payload} = DeltaCompression.maybe_encode(base_hash, base, content)
    assert {:ok, _} = Storage.put(Project.blob_key(repository_id, base_hash), base, opts)
    assert {:ok, _} = Storage.put(Project.blob_key(repository_id, new_hash), payload, opts)

    assert {:ok, ^content} = Project.get_blob(repository_id, new_hash, opts)
  end

  test "decode enforces max depth for nested delta payloads" do
    base = String.duplicate("a", 64) <> "0" <> String.duplicate("a", 64)
    content1 = String.duplicate("a", 64) <> "1" <> String.duplicate("a", 64)
    content2 = String.duplicate("a", 64) <> "2" <> String.duplicate("a", 64)
    base_hash = :crypto.hash(:sha256, base)
    content1_hash = :crypto.hash(:sha256, content1)

    assert {:ok, payload1} = DeltaCompression.maybe_encode(base_hash, base, content1)
    assert {:ok, payload2} = DeltaCompression.maybe_encode(content1_hash, content1, content2)

    fetch = fn
      ^content1_hash -> {:ok, payload1}
      ^base_hash -> {:ok, base}
      _ -> {:error, :not_found}
    end

    assert {:error, :delta_depth_exceeded} =
             DeltaCompression.decode(payload2, fetch, max_depth: 1)

    assert {:ok, ^content2} = DeltaCompression.decode(payload2, fetch, max_depth: 2)
  end

  test "decode rejects payloads with impossible prefix and suffix lengths" do
    base = "abc"
    base_hash = :crypto.hash(:sha256, base)

    payload =
      <<"MICDELTA", 1, base_hash::binary, 3::unsigned-big-32, 3::unsigned-big-32,
        0::unsigned-big-32>>

    fetch = fn
      ^base_hash -> {:ok, base}
      _ -> {:error, :not_found}
    end

    assert {:error, :invalid_delta_payload} = DeltaCompression.decode(payload, fetch)
  end
end
