defmodule MicelioWeb.LayoutsTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MicelioWeb.Layouts

  test "shows legal links on marketing pages" do
    html = render_layout("/")

    assert html =~ "site-footer-nav"
    assert html =~ "href=\"/terms\""
    assert html =~ "href=\"/privacy\""
    assert html =~ "href=\"/cookies\""
    assert html =~ "href=\"/impressum\""
  end

  test "hides legal links on repository pages" do
    html = render_layout("/org/repository")

    refute html =~ "site-footer-nav"
    refute html =~ "href=\"/terms\""
    refute html =~ "href=\"/privacy\""
    refute html =~ "href=\"/cookies\""
    refute html =~ "href=\"/impressum\""
  end

  defp render_layout(current_path) do
    render_component(&Layouts.app/1,
      flash: %{},
      current_path: current_path,
      inner_block: [
        %{__slot__: :inner_block, inner_block: fn _, _ -> "Repository workspace" end}
      ]
    )
  end
end
