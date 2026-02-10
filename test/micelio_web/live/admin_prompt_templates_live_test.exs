defmodule MicelioWeb.AdminPromptTemplatesLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts

  test "creates prompt templates from the admin view", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/prompt-templates")

    form =
      form(view, "#prompt-template-form",
        prompt_template: %{
          name: "Release notes",
          description: "Summarize changes for release",
          category: "Docs",
          system_prompt: "System template",
          prompt: "Summarize the changes"
        }
      )

    render_submit(form)

    html = render(view)
    assert html =~ "Prompt templates"
    assert html =~ "Release notes"
    assert html =~ "Pending"
  end
end
