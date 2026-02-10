defmodule MicelioWeb.Browser.AdminControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.PromptRequests
  alias Micelio.Repositories
  alias Micelio.Sessions

  test "denies access to non-admin users", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("user@example.com")

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You do not have access to that page."
  end

  test "shows admin dashboard for admins", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    {:ok, organization} = Accounts.create_organization(%{name: "Acme", handle: "acme"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        name: "Acme Repo",
        handle: "acme-repo",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-1",
        goal: "Ship overview",
        repository_id: repository.id,
        user_id: admin.id
      })

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin")

    html = html_response(conn, 200)
    assert html =~ "Admin dashboard"
    assert html =~ "id=\"admin-dashboard\""
    assert html =~ "id=\"admin-metrics\""
    assert html =~ "id=\"admin-metric-admin-users\""
    assert html =~ "id=\"admin-metric-admin-emails\""
    assert html =~ "id=\"admin-access\""
    assert html =~ "id=\"admin-admins-list\""
    assert html =~ "id=\"admin-email-0\""
    assert html =~ "id=\"admin-users-list\""
    assert html =~ "id=\"admin-organizations-list\""
    assert html =~ "id=\"admin-repositories-list\""
    assert html =~ "id=\"admin-sessions-list\""
    assert html =~ "id=\"admin-metric-public-repositories\""
    assert html =~ "id=\"admin-metric-private-repositories\""
    assert html =~ "id=\"admin-user-#{admin.id}\""
    assert html =~ "id=\"admin-user-role-#{admin.id}\""
    assert html =~ "id=\"admin-organization-#{organization.id}\""
    assert html =~ "id=\"admin-project-#{repository.id}\""
    assert html =~ "id=\"admin-session-#{session.id}\""
  end

  test "shows empty states when there is no activity yet", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin")

    html = html_response(conn, 200)
    assert html =~ "No organizations yet."
    assert html =~ "No repositories yet."
    assert html =~ "No sessions yet."
  end

  test "shows usage dashboard with token metrics", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(admin, %{name: "Acme", handle: "acme"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        name: "Acme Repo",
        handle: "acme-repo",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Add usage dashboard",
          prompt: "Build the usage dashboard.",
          result: "Done",
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "hi"}]},
          origin: :ai_generated,
          model: "gpt-4",
          model_version: "2024-01-01",
          token_count: 120,
          generated_at: DateTime.utc_now()
        },
        project: repository,
        user: admin
      )

    {:ok, _} = PromptRequests.review_prompt_request(prompt_request, admin, :accepted)

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin/usage")

    html = html_response(conn, 200)
    assert html =~ "Usage dashboard"
    assert html =~ "id=\"admin-usage-dashboard\""
    assert html =~ "id=\"admin-usage-overview\""
    assert html =~ "id=\"admin-usage-repositories\""
    assert html =~ "id=\"admin-usage-repositories-list\""
    assert html =~ "id=\"admin-usage-project-#{repository.id}\""
  end

  test "shows empty usage dashboard when no prompt requests exist", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin/usage")

    html = html_response(conn, 200)
    assert html =~ "Usage dashboard"
    assert html =~ "No usage yet."
    assert html =~ "id=\"admin-usage-overview\""
  end
end
