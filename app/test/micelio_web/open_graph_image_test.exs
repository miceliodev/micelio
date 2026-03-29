defmodule MicelioWeb.OpenGraphImageTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.OpenGraphImage

  test "renders commit og image template as HTML" do
    attrs = %{
      "image_template" => "commit",
      "title" => "Fix auth token refresh",
      "description" => "Ensure refresh flow updates tokens.",
      "site_name" => "Micelio",
      "canonical_url" => "https://micelio.dev/org/repo/commit/abc123",
      "image_stats" => %{"files" => 4, "additions" => 12, "deletions" => 3}
    }

    html = OpenGraphImage.render_html(attrs)

    assert String.contains?(html, "FILES")
    assert String.contains?(html, "4")
    assert String.contains?(html, "ADDITIONS")
    assert String.contains?(html, "12")
    assert String.contains?(html, "DELETIONS")
    assert String.contains?(html, "3")
    assert String.contains?(html, "Commit")
  end

  test "renders pull request og image template as HTML" do
    attrs = %{
      "image_template" => "pull_request",
      "title" => "Add repository import pipeline",
      "description" => "Bring in git history and metadata.",
      "site_name" => "Micelio",
      "canonical_url" => "https://micelio.dev/org/repo/pulls/42",
      "image_stats" => %{"commits" => 5, "files" => 18, "comments" => 9}
    }

    html = OpenGraphImage.render_html(attrs)

    assert String.contains?(html, "COMMITS")
    assert String.contains?(html, "5")
    assert String.contains?(html, "FILES")
    assert String.contains?(html, "18")
    assert String.contains?(html, "COMMENTS")
    assert String.contains?(html, "9")
    assert String.contains?(html, "Pull Requests")
  end

  test "renders default template with title and description" do
    attrs = %{
      "title" => "Welcome to Micelio",
      "description" => "An agent-first forge.",
      "site_name" => "Micelio",
      "canonical_url" => "https://micelio.dev/"
    }

    html = OpenGraphImage.render_html(attrs)

    assert String.contains?(html, "Welcome to Micelio")
    assert String.contains?(html, "An agent-first forge.")
    assert String.contains?(html, "micelio.dev/")
  end
end
