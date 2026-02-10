defmodule MicelioWeb.RepositoryWebhooksLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Repositories
  alias Micelio.Webhooks

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  test "creates a webhook from the webhooks page", %{conn: conn} do
    handle = unique_handle("webhooks")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "org-#{handle}",
        name: "Webhooks Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "repo-#{handle}",
        name: "Webhooks Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks")

    assert has_element?(view, "#webhook-form")

    form =
      form(view, "#webhook-form",
        webhook: %{
          url: "https://hooks.example.com/push",
          events: ["push"],
          secret: "super-secret"
        }
      )

    render_submit(form)

    [webhook] = Webhooks.list_webhooks_for_repository(repository.id)
    assert webhook.url == "https://hooks.example.com/push"
    assert webhook.events == ["push"]
  end

  test "toggles and deletes a webhook", %{conn: conn} do
    handle = unique_handle("toggle")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "org-#{handle}",
        name: "Webhooks Toggle Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "repo-#{handle}",
        name: "Webhooks Toggle Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, webhook} =
      Webhooks.create_webhook(%{
        repository_id: repository.id,
        url: "https://hooks.example.com/landing",
        events: ["session.landed"],
        active: true
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks")

    view
    |> element("#webhook-toggle-#{webhook.id}")
    |> render_click()

    updated = Webhooks.get_webhook_for_project(repository.id, webhook.id)
    assert updated.active == false

    view
    |> element("#webhook-delete-#{webhook.id}")
    |> render_click()

    assert Webhooks.get_webhook_for_project(repository.id, webhook.id) == nil
  end

  test "requires authentication", %{conn: conn} do
    handle = unique_handle("auth")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "org-#{handle}",
        name: "Webhooks Auth Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "repo-#{handle}",
        name: "Webhooks Auth Repo",
        organization_id: organization.id
      })

    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(
               conn,
               ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks"
             )
  end

  test "requires admin access", %{conn: conn} do
    handle = unique_handle("access")
    {:ok, owner} = Accounts.get_or_create_user_by_email("owner-#{handle}@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("member-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "org-#{handle}",
        name: "Webhooks Access Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "repo-#{handle}",
        name: "Webhooks Access Repo",
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
             live(
               conn,
               ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks"
             )

    assert redirect_to == ~p"/#{organization.account.handle}/#{repository.handle}"
  end
end
