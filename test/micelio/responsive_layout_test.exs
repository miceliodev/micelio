defmodule Micelio.ResponsiveLayoutTest do
  use ExUnit.Case, async: true

  defp css_path(path) do
    Path.expand(Path.join(["../..", path]), __DIR__)
  end

  test "sessions css includes mobile layout adjustments" do
    css = File.read!(css_path("assets/css/routes/sessions.css"))

    assert css =~ "@media (max-width: 40rem)"
    assert css =~ ".session-show-actions"
  end

  test "projects css includes mobile layout adjustments" do
    css = File.read!(css_path("assets/css/routes/projects.css"))

    assert css =~ "@media (max-width: 40rem)"
    assert css =~ ".project-show-navigation"
    assert css =~ ".session-card-content"
  end

  test "account profile css includes mobile layout adjustments" do
    css = File.read!(css_path("assets/css/routes/account_profile.css"))

    assert css =~ "@media (max-width: 40rem)"
    assert css =~ ".account-profile-header"
    assert css =~ ".account-passkey-entry"
  end

  test "account profile activity spacing is compact" do
    css = File.read!(css_path("assets/css/routes/account_profile.css"))

    assert css =~ "#account-activity .account-section-title"
    assert css =~ "gap: 0;"
  end

  test "project show css includes mobile tree adjustments" do
    css = File.read!(css_path("assets/css/routes/project_show.css"))

    assert css =~ "@media (max-width: 40rem)"
    assert css =~ ".repository-tree-link"
  end
end
