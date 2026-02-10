defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "Turbopuffer-inspired theme colors are defined in tokens.css" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Light mode colors (nature-inspired)
    assert tokens =~ "--theme-ui-colors-background: #f8f5ef;"
    assert tokens =~ "--theme-ui-colors-text: #1f3324;"
    assert tokens =~ "--theme-ui-colors-accent: #2f7c4c;"
    assert tokens =~ "--theme-ui-colors-border: #c6d1c4;"
  end

  test "Turbopuffer activity graph colors" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Green activity colors
    assert tokens =~ "--theme-ui-colors-activity-0: #e6ede4;"
    assert tokens =~ "--theme-ui-colors-activity-1: #bcd7b8;"
    assert tokens =~ "--theme-ui-colors-activity-2: #8abf8c;"
    assert tokens =~ "--theme-ui-colors-activity-3: #4f995d;"
    assert tokens =~ "--theme-ui-colors-activity-4: #2f7c4c;"
  end

  test "profile activity graph styles use theme tokens" do
    styles = File.read!("assets/css/routes/account_profile.css")

    assert styles =~ "--activity-graph-0: var(--theme-ui-colors-activity-0);"
    assert styles =~ "--activity-graph-1: var(--theme-ui-colors-activity-1);"
    assert styles =~ "--activity-graph-2: var(--theme-ui-colors-activity-2);"
    assert styles =~ "--activity-graph-3: var(--theme-ui-colors-activity-3);"
    assert styles =~ "--activity-graph-4: var(--theme-ui-colors-activity-4);"
    assert styles =~ ".activity-graph {\n  margin: 0;\n}"
  end
end
