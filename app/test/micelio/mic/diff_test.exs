defmodule Micelio.Mic.DiffTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.Diff

  describe "unified_diff/4" do
    test "returns nil when both contents are nil" do
      assert {:ok, nil} = Diff.unified_diff(nil, nil, "file.txt")
    end

    test "returns nil when contents are identical" do
      content = "hello\nworld\n"
      assert {:ok, nil} = Diff.unified_diff(content, content, "file.txt")
    end

    test "generates diff for added file" do
      {:ok, diff} = Diff.unified_diff(nil, "line1\nline2\n", "new.txt")
      assert diff =~ "--- a/new.txt"
      assert diff =~ "+++ b/new.txt"
      assert diff =~ "+line1"
      assert diff =~ "+line2"
    end

    test "generates diff for deleted file" do
      {:ok, diff} = Diff.unified_diff("line1\nline2\n", nil, "old.txt")
      assert diff =~ "--- a/old.txt"
      assert diff =~ "+++ b/old.txt"
      assert diff =~ "-line1"
      assert diff =~ "-line2"
    end

    test "generates diff for modified file" do
      old = "line1\nline2\nline3\n"
      new = "line1\nchanged\nline3\n"

      {:ok, diff} = Diff.unified_diff(old, new, "mod.txt")
      assert diff =~ "--- a/mod.txt"
      assert diff =~ "+++ b/mod.txt"
      assert diff =~ "-line2"
      assert diff =~ "+changed"
      assert diff =~ " line1"
      assert diff =~ " line3"
    end

    test "includes hunk headers" do
      old = "a\nb\nc\n"
      new = "a\nx\nc\n"

      {:ok, diff} = Diff.unified_diff(old, new, "test.txt")
      assert diff =~ "@@"
    end

    test "handles empty strings" do
      {:ok, diff} = Diff.unified_diff("", "hello\n", "file.txt")
      assert diff =~ "+hello"
    end
  end
end
