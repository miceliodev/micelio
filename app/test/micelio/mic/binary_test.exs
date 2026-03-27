defmodule Micelio.Mic.BinaryTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.Binary
  alias Micelio.Sessions.Conflict

  describe "encode_filter_index/1 and decode_filter_index/1" do
    test "roundtrips filter indexes" do
      filter = Conflict.build_filter(["lib/a.ex"], size: 128, hash_count: 3)

      encoded = Binary.encode_filter_index(filter)
      assert {:ok, decoded} = Binary.decode_filter_index(encoded)
      assert decoded["size"] == 128
      assert decoded["hash_count"] == 3
      assert Conflict.might_conflict?(decoded, "lib/a.ex")
    end
  end

  describe "encode_path_index/1 and decode_path_index/1" do
    test "roundtrips path indexes" do
      paths = ["lib/a.ex", "priv/static/logo.png"]

      encoded = Binary.encode_path_index(paths)
      assert {:ok, decoded} = Binary.decode_path_index(encoded)
      assert decoded == paths
    end

    test "rejects invalid payloads" do
      assert {:error, :invalid_path_index} = Binary.decode_path_index("bad")
    end
  end

  describe "encode_rollup_checkpoint/1 and decode_rollup_checkpoint/1" do
    test "roundtrips checkpoint values" do
      encoded = Binary.encode_rollup_checkpoint(1234)
      assert {:ok, 1234} = Binary.decode_rollup_checkpoint(encoded)
    end

    test "rejects invalid checkpoints" do
      assert {:error, :invalid_checkpoint} = Binary.decode_rollup_checkpoint("bad")
    end
  end
end
