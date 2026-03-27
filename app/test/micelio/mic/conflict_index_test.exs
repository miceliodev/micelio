defmodule Micelio.Mic.ConflictIndexTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.ConflictIndex
  alias Micelio.Sessions.Conflict

  describe "expand_ranges_with/5" do
    test "expands ranges into level-1 blocks when rollups are missing" do
      loader = fn _repository_id, _level, _start_pos -> {:ok, nil} end

      ranges = ConflictIndex.expand_ranges_with("proj", 1, 150, ["lib/a.ex"], loader)

      assert ranges == [{1, 100}, {101, 150}]
    end

    test "skips full blocks when rollup shows no conflicts" do
      filter = Conflict.build_filter(["lib/a.ex"], size: 128, hash_count: 3)
      loader = fn _repository_id, _level, _start_pos -> {:ok, filter} end

      assert ConflictIndex.expand_ranges_with("proj", 1, 100, [], loader) == []
    end
  end

  describe "rollup_starts/3" do
    test "returns aligned rollup starts within a range" do
      assert ConflictIndex.rollup_size(1) == 100

      assert ConflictIndex.rollup_starts(100, 1, 250) == [1, 101, 201]
      assert ConflictIndex.rollup_starts(100, 50, 99) == [1]
      assert ConflictIndex.rollup_starts(100, 101, 200) == [101]
    end

    test "returns empty list for inverted ranges" do
      assert ConflictIndex.rollup_starts(100, 10, 1) == []
    end
  end
end
