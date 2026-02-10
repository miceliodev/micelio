defmodule MicelioWeb.AccountProfileStylesTest do
  use ExUnit.Case, async: true

  test "activity title spacing is tight for the graph" do
    css = File.read!("assets/css/routes/account_profile.css")

    assert css =~ "#account-activity .account-section-title"
    assert css =~ "gap: 0;"
    # Activity colors now use theme token variables
    assert css =~ "--activity-graph-0: var(--theme-ui-colors-activity-0);"
    assert css =~ "--activity-graph-4: var(--theme-ui-colors-activity-4);"
    assert css =~ "margin: 0;"
    assert css =~ "line-height: 1;"
    assert css =~ ".activity-graph {\n  margin: 0;\n}"
  end
end
