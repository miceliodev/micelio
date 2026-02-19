defmodule MicelioWeb.RepositoryLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Repositories

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

  test "lists projects for the current user and supports delete", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-live"))
    org_handle = unique_handle("live-org")
    repository_handle = unique_handle("live-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Live Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repository_handle,
        name: "Live Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/repositories")

    assert has_element?(view, "#new-project-link")
    assert has_element?(view, "#project-view-#{repository.id}")

    view
    |> element("#project-delete-#{repository.id}")
    |> render_click()

    refute has_element?(view, "#project-view-#{repository.id}")
    assert Repositories.get_repository(repository.id) == nil
  end

  test "creates a repository from the new form", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-create"))
    org_handle = unique_handle("create-org")
    repository_handle = unique_handle("live-created")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Create Org"
      })

    conn = login_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/repositories/new")

    form =
      form(view, "#repository-form",
        repository: %{
          organization_id: organization.id,
          name: "Live Created",
          handle: repository_handle,
          description: "Created from LiveView",
          visibility: "public"
        }
      )

    render_submit(form)

    repository = Repositories.get_repository_by_handle(organization.id, repository_handle)
    assert repository.visibility == "public"

    assert_redirect(view, ~p"/#{organization.account.handle}/#{repository_handle}")
  end

  test "updates a repository from the edit form", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-edit"))
    org_handle = unique_handle("edit-org")
    repository_handle = unique_handle("edit-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Edit Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repository_handle,
        name: "Edit Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository_handle}/edit")

    form =
      form(view, "#repository-form",
        repository: %{
          name: "Updated Project",
          handle: repository_handle,
          description: "Updated",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Repositories.get_repository(repository.id)
    assert updated.visibility == "public"

    assert_redirect(view, ~p"/#{organization.account.handle}/#{repository_handle}")
  end
end
