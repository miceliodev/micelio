defmodule Micelio.Sessions.BlameTest do
  use ExUnit.Case, async: true

  alias Micelio.Sessions.Blame

  test "returns nil attributions when no changes exist" do
    content = "one\ntwo"

    lines = Blame.build_lines(content, [])

    assert Enum.map(lines, & &1.attribution) == [nil, nil]
  end

  test "preserves attribution across modifications" do
    initial_change = %{change_type: "added", content: "one\ntwo"}
    update_change = %{change_type: "modified", content: "one\ntwo\nthree"}

    lines = Blame.build_lines("one\ntwo\nthree", [initial_change, update_change])

    assert Enum.at(lines, 0).attribution == initial_change
    assert Enum.at(lines, 1).attribution == initial_change
    assert Enum.at(lines, 2).attribution == update_change
  end
end
