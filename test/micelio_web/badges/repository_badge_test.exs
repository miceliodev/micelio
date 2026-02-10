defmodule MicelioWeb.Badges.ProjectBadgeTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.Badges.ProjectBadge

  test "renders an svg badge with calculated widths" do
    svg = ProjectBadge.render("org/repo", "5 stars")

    assert svg =~ "<svg"
    assert svg =~ "width=\"110\""
    assert svg =~ "<rect width=\"58\""
    assert svg =~ ~s(<rect x="58" width="52")
    assert svg =~ "org/repo"
    assert svg =~ "5 stars"
  end

  test "escapes label and message content" do
    svg = ProjectBadge.render("org/<script>", "0 <stars>")

    assert svg =~ "org/&lt;script&gt;"
    assert svg =~ "0 &lt;stars&gt;"
    assert svg =~ "aria-label=\"org/&lt;script&gt;: 0 &lt;stars&gt;\""
  end
end
