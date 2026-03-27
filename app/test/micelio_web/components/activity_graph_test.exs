defmodule MicelioWeb.ActivityGraphComponentTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MicelioWeb.CoreComponents

  test "renders activity graph for provided counts" do
    today = Date.utc_today()

    html =
      render_component(&CoreComponents.activity_graph/1,
        activity_counts: %{today => 2},
        weeks: 1
      )

    assert html =~ "activity-graph"
    assert html =~ "aria-label=\"2 contributions\""
    assert html =~ "data-date=\"#{Date.to_iso8601(today)}\""
    assert html =~ "data-count=\"2\""
  end

  test "renders legend levels for styling consistency" do
    today = Date.utc_today()

    html =
      render_component(&CoreComponents.activity_graph/1,
        activity_counts: %{today => 1},
        weeks: 1
      )

    assert html =~ "activity-graph-legend"
    assert html =~ "activity-graph-cell--0"
    assert html =~ "activity-graph-cell--1"
    assert html =~ "activity-graph-cell--2"
    assert html =~ "activity-graph-cell--3"
    assert html =~ "activity-graph-cell--4"
  end

  test "sizes the activity graph SVG based on week count" do
    today = Date.utc_today()

    html =
      render_component(&CoreComponents.activity_graph/1,
        activity_counts: %{today => 1},
        weeks: 2
      )

    assert html =~ "activity-graph-svg"
    assert html =~ "width=\"28\""
    assert html =~ "height=\"98\""
  end

  test "activity graph styles use theme token variables" do
    css_path = Path.join(File.cwd!(), "assets/css/routes/account_profile.css")
    css = File.read!(css_path)

    # Activity colors now use theme token variables
    assert css =~ "--activity-graph-0: var(--theme-ui-colors-activity-0);"
    assert css =~ "--activity-graph-4: var(--theme-ui-colors-activity-4);"
    assert css =~ "#account-activity .account-section-title"
    assert css =~ "margin: 0;"
    assert css =~ "line-height: 1;"
    assert css =~ "background-color: var(--activity-graph-1);"
  end
end
