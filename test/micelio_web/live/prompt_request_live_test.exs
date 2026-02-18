defmodule MicelioWeb.PlanLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Plans
  alias Micelio.Repo

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  defp unique_email(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}@example.com"
  end

  defp setup_repository do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("prompt-live"))
    org_handle = unique_handle("prompt-live-org")
    repository_handle = unique_handle("prompt-live-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Prompt Live Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repository_handle,
        name: "Prompt Live Repo",
        organization_id: organization.id
      })

    {user, organization, repository}
  end

  test "lists plans and creates a new plan via form", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs"
      )

    assert has_element?(view, "#new-plan")
    assert has_element?(view, "#plans-empty")

    {:ok, new_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs/new"
      )

    assert has_element?(new_view, "#plan-form")
    assert has_element?(new_view, "#plan-title")
    assert has_element?(new_view, "#plan-submit")

    new_view
    |> form("#plan-form", plan: %{title: "My new plan", description: "Plan description"})
    |> render_submit()

    [plan] = Plans.list_plans_for_repository(repository)
    assert plan.number == 1
    assert plan.title == "My new plan"
    assert plan.description == "Plan description"
  end

  test "shows a plan", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_simple_plan(
        %{"title" => "Review this", "description" => "Some description"},
        repository: repository,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{plan.number}"
      )

    assert html =~ "Review this"
    assert html =~ "##{plan.number}"
    assert has_element?(view, "#plan-description")
  end

  test "shows draft PR and sandbox links when metadata is available", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_simple_plan(
        %{"title" => "Preview this", "description" => "Sandbox metadata"},
        repository: repository,
        user: user
      )

    {:ok, plan} =
      plan
      |> Micelio.Plans.Plan.forge_pr_changeset(%{
        forge_branch_name: "micelio/#{plan.id}",
        forge_pr_provider: "github",
        forge_pr_number: 1,
        forge_pr_url: "https://github.com/example/repo/pull/1",
        forge_pr_state: "draft",
        forge_pr_draft: true
      })
      |> Repo.update()

    {:ok, _plan} =
      plan
      |> Micelio.Plans.Plan.sandbox_changeset(%{
        sandbox_status: "running",
        sandbox_metadata: %{
          "preview_url" => "https://preview.example.com",
          "dashboard_url" => "https://app.daytona.io/sandboxes/abc"
        }
      })
      |> Repo.update()

    conn = login_user(conn, user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{plan.number}"
      )

    assert html =~ "View draft PR"
    assert html =~ "Open preview"
    assert html =~ "Open sandbox"
    assert has_element?(view, "a[href='https://preview.example.com']")
    assert has_element?(view, "a[href='https://app.daytona.io/sandboxes/abc']")
  end

  test "assigns sequential numbers to plans", %{conn: _conn} do
    {user, _organization, repository} = setup_repository()

    {:ok, pr1} =
      Plans.create_simple_plan(
        %{"title" => "First"},
        repository: repository,
        user: user
      )

    {:ok, pr2} =
      Plans.create_simple_plan(
        %{"title" => "Second"},
        repository: repository,
        user: user
      )

    assert pr1.number == 1
    assert pr2.number == 2
  end

  test "index shows plan list when not empty", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, _pr} =
      Plans.create_simple_plan(
        %{"title" => "A plan"},
        repository: repository,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs"
      )

    assert html =~ "A plan"
    assert has_element?(view, "#plans-list")
    refute has_element?(view, "#plans-empty")
  end
end
