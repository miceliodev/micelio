defmodule Micelio.Mic.ProjectTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.Project

  test "list_entries returns directories before files and sorts by name" do
    tree = %{
      "b/file.txt" => <<1>>,
      "a/file.txt" => <<2>>,
      "b.txt" => <<3>>,
      "a.txt" => <<4>>,
      "b/inner/leaf.md" => <<5>>,
      "a/inner.md" => <<6>>
    }

    entries = Project.list_entries(tree, "")

    assert Enum.map(entries, & &1.name) == ["a", "b", "a.txt", "b.txt"]
    assert Enum.map(entries, & &1.type) == [:tree, :tree, :blob, :blob]
  end

  test "list_entries scopes results to a directory" do
    tree = %{
      "lib/app.ex" => <<1>>,
      "lib/utils/helpers.ex" => <<2>>,
      "README.md" => <<3>>
    }

    entries = Project.list_entries(tree, "lib")

    assert Enum.map(entries, & &1.path) == ["lib/utils", "lib/app.ex"]
    assert Enum.map(entries, & &1.type) == [:tree, :blob]
  end

  test "directory_exists? checks tree prefixes for nested paths" do
    tree = %{
      "lib/app.ex" => <<1>>,
      "lib/utils/helpers.ex" => <<2>>
    }

    assert Project.directory_exists?(tree, "lib")
    assert Project.directory_exists?(tree, "lib/utils")
    refute Project.directory_exists?(tree, "priv")
  end
end
