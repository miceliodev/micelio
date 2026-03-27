defmodule MicelioWeb.Browser.SearchControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts

  test "renders results for public repositories", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "search-org-#{unique}",
        name: "Search Org #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "public-repo-#{unique}",
        name: "Public Searchable",
        description: "Searchable repository",
        organization_id: organization.id,
        visibility: "public"
      })

    conn = get(conn, ~p"/search?q=searchable")
    html = html_response(conn, 200)

    assert html =~ "repository-search-result-#{repository.id}"
    assert html =~ "#{organization.account.handle}/#{repository.handle}"
  end

  test "hides private repositories from anonymous users", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "private-org-#{unique}",
        name: "Private Org #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "private-repo-#{unique}",
        name: "Private Search",
        description: "Hidden search target",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/search?q=hidden")
    html = html_response(conn, 200)

    refute html =~ "repository-search-result-#{repository.id}"
  end

  test "shows private repositories to organization members", %{conn: conn} do
    unique = System.unique_integer([:positive])
    {:ok, user} = Accounts.get_or_create_user_by_email("member-#{unique}@example.com")
    conn = log_in_user(conn, user)

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "member-org-#{unique}",
        name: "Member Org #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "member-repo-#{unique}",
        name: "Member Search",
        description: "Private search for members",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/search?q=member")
    html = html_response(conn, 200)

    assert html =~ "repository-search-result-#{repository.id}"
  end
end
