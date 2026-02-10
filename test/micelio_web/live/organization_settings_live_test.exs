defmodule MicelioWeb.OrganizationSettingsLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  test "updates organization LLM settings", %{conn: conn} do
    handle = unique_handle("org-settings")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: handle,
        name: "Org Settings"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/organizations/#{organization.account.handle}/settings")

    assert has_element?(view, "#organization-settings-form")

    form =
      form(view, "#organization-settings-form",
        account: %{
          llm_models: ["gpt-4.1"],
          llm_default_model: "gpt-4.1"
        }
      )

    render_submit(form)

    updated = Accounts.get_organization(organization.id)
    updated_account = Micelio.Repo.preload(updated, :account).account
    assert updated_account.llm_models == ["gpt-4.1"]
    assert updated_account.llm_default_model == "gpt-4.1"

    assert_redirect(view, ~p"/#{organization.account.handle}")
  end

  test "requires authentication", %{conn: conn} do
    handle = unique_handle("org-auth")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: handle,
        name: "Org Settings Auth"
      })

    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(conn, ~p"/organizations/#{organization.account.handle}/settings")
  end

  test "requires admin access", %{conn: conn} do
    handle = unique_handle("org-access")
    {:ok, owner} = Accounts.get_or_create_user_by_email("owner-#{handle}@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("member-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: handle,
        name: "Org Settings Access"
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
               flash: %{"error" => "You do not have access to this organization."}
             }}} =
             live(conn, ~p"/organizations/#{organization.account.handle}/settings")

    assert redirect_to == ~p"/#{organization.account.handle}"
  end
end
