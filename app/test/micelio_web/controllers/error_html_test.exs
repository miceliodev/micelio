defmodule MicelioWeb.Browser.ErrorHTMLTest do
  use MicelioWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(MicelioWeb.Browser.ErrorHTML, "404", "html", [])

    assert html =~ "Page not found"
    assert html =~ "Go home"
    assert html =~ "Go back"
  end

  test "renders 500.html" do
    html = render_to_string(MicelioWeb.Browser.ErrorHTML, "500", "html", [])

    assert html =~ "Something went wrong"
    assert html =~ "Go home"
    assert html =~ "Go back"
  end
end
