defmodule MicelioWeb.Browser.SkillMdTest do
  use MicelioWeb.ConnCase, async: true

  test "serves the agent skill guide", %{conn: conn} do
    conn = get(conn, "/skill.md")

    assert conn.status == 200
  end

  test "agent guide stays aligned with AGENTS.md" do
    agents_path = Path.expand("../AGENTS.md", File.cwd!())
    skill_path = Path.expand("priv/static/skill.md", File.cwd!())

    assert File.exists?(agents_path)
    assert File.exists?(skill_path)
  end
end
