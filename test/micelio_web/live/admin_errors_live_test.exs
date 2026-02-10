defmodule MicelioWeb.AdminErrorsLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Errors

  defp create_error(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Errors.create_error(
      Map.merge(
        %{
          fingerprint: "error-fp-#{System.unique_integer()}",
          kind: :exception,
          message: "boom",
          severity: :error,
          occurred_at: now,
          occurrence_count: 1,
          first_seen_at: now,
          last_seen_at: now
        },
        attrs
      )
    )
  end

  test "shows error dashboard for admins", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    {:ok, error} = create_error(%{message: "dashboard error"})

    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/admin/errors")

    assert html =~ "id=\"admin-errors\""
    assert has_element?(view, "#admin-errors-overview")
    assert has_element?(view, "#admin-error-#{error.id}")
  end

  test "resolves errors from the list", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    {:ok, error} = create_error(%{message: "resolve me"})

    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/errors")

    view
    |> element("#admin-error-#{error.id} button", "Resolve")
    |> render_click()

    assert Errors.get_error!(error.id).resolved_at != nil
  end

  test "shows error detail view", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    {:ok, error} =
      create_error(%{
        message: "details",
        stacktrace: "stacktrace line"
      })

    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/admin/errors/#{error.id}")

    assert html =~ "Copy stacktrace"
    assert has_element?(view, "#admin-error-stacktrace")
  end

  test "requires admin access", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("member@example.com")
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/errors")
  end
end
