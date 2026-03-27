defmodule MicelioWeb.OpenGraphImageTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.OpenGraphImage

  test "renders commit og image template" do
    attrs = %{
      "image_template" => "commit",
      "title" => "Fix auth token refresh",
      "description" => "Ensure refresh flow updates tokens.",
      "site_name" => "Micelio",
      "canonical_url" => "https://micelio.dev/org/repo/commit/abc123",
      "image_stats" => %{"files" => 4, "additions" => 12, "deletions" => 3}
    }

    svg = OpenGraphImage.render_svg(attrs)

    assert String.contains?(svg, "Commit Open Graph image")
    assert String.contains?(svg, "FILES")
    assert String.contains?(svg, "4")
    assert String.contains?(svg, "ADDITIONS")
    assert String.contains?(svg, "12")
    assert String.contains?(svg, "DELETIONS")
    assert String.contains?(svg, "3")
  end

  test "renders pull request og image template" do
    attrs = %{
      "image_template" => "pull_request",
      "title" => "Add repository import pipeline",
      "description" => "Bring in git history and metadata.",
      "site_name" => "Micelio",
      "canonical_url" => "https://micelio.dev/org/repo/pulls/42",
      "image_stats" => %{"commits" => 5, "files" => 18, "comments" => 9}
    }

    svg = OpenGraphImage.render_svg(attrs)

    assert String.contains?(svg, "Pull request Open Graph image")
    assert String.contains?(svg, "COMMITS")
    assert String.contains?(svg, "5")
    assert String.contains?(svg, "FILES")
    assert String.contains?(svg, "18")
    assert String.contains?(svg, "COMMENTS")
    assert String.contains?(svg, "9")
  end
end
