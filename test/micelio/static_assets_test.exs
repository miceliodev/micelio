defmodule Micelio.StaticAssetsTest do
  use ExUnit.Case, async: true

  test "skill.md stays aligned with AGENTS.md" do
    root = Path.expand("../..", __DIR__)
    agents_path = Path.join(root, "AGENTS.md")
    skill_path = Path.join(root, "priv/static/skill.md")

    assert File.read!(agents_path) == File.read!(skill_path)
  end
end
