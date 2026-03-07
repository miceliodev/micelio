defmodule MicelioWeb.RepositorySettingsLiveTest do
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

  test "updates repository settings from the settings page", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("repo-settings"))
    org_handle = unique_handle("settings-org")
    repo_handle = unique_handle("settings-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Settings Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Settings Repo",
        description: "Original description",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    assert has_element?(view, "#repository-settings-form")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: "Updated Repo",
          description: "Updated description",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Repositories.get_repository(repository.id)
    assert updated.name == "Updated Repo"
    assert updated.description == "Updated description"
    assert updated.visibility == "public"

    assert_redirect(view, ~p"/#{organization.account.handle}/#{repository.handle}")
  end

  test "ignores handle changes from the settings page", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-handle"))
    org_handle = unique_handle("handle-settings-org")
    repo_handle = unique_handle("handle-settings-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Handle Settings Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Handle Settings Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: "Handle Settings Repo Updated",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Repositories.get_repository(repository.id)
    assert updated.handle == repo_handle
    assert updated.name == "Handle Settings Repo Updated"
  end

  test "requires authentication", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-auth"))
    org_handle = unique_handle("auth-settings-org")
    repo_handle = unique_handle("auth-settings-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Auth Settings Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Auth Settings Repo",
        organization_id: organization.id
      })

    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")
  end

  test "requires admin access", %{conn: conn} do
    {:ok, owner} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-owner"))
    {:ok, member} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-member"))
    org_handle = unique_handle("settings-access-org")
    repo_handle = unique_handle("settings-access-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: org_handle,
        name: "Settings Access Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Settings Access Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "member"
      })

    conn = login_user(conn, member)

    assert {:error,
            {:live_redirect,
             %{
               to: redirect_to,
               flash: %{"error" => "You do not have access to this repository."}
             }}} =
             live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    assert redirect_to == ~p"/#{organization.account.handle}/#{repository.handle}"
  end

  test "shows validation errors when required fields are missing", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-errors"))
    org_handle = unique_handle("settings-errors-org")
    repo_handle = unique_handle("settings-errors-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Settings Errors Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Settings Errors Repo",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    refute has_element?(view, "#repository-settings-form .form-error")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: ""
        }
      )

    render_change(form)

    assert has_element?(view, "#repository-settings-form .form-error")
  end

  test "keeps repository param names after submit errors", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("repo-settings-form-name"))
    org_handle = unique_handle("settings-form-name-org")
    repo_handle = unique_handle("settings-form-name-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Settings Form Name Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repo_handle,
        name: "Settings Form Name Repo",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    form =
    form(view, "#repository-settings-form",
        repository: %{
          name: ""
        }
      )

    render_submit(form)

    assert has_element?(view, "input[name='repository[name]']")
    assert has_element?(view, "textarea[name='repository[description]']")
  end
end
