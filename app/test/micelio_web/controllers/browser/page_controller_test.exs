defmodule MicelioWeb.Browser.PageControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts

  test "renders popular projects for anonymous users", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "popular-home-#{unique}",
        name: "Popular Home #{unique}"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "popular-home-project-#{unique}",
        name: "Popular Home Project",
        description: "Popular home description",
        organization_id: organization.id,
        visibility: "public"
      })

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "popular-repositories"
    assert html =~ "popular-project-#{repository.id}"
    assert html =~ "#{organization.account.handle}/#{repository.handle}"
  end

  test "shows pagination when more popular projects exist", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "popular-page-#{unique}",
        name: "Popular Page #{unique}"
      })

    Enum.each(1..7, fn index ->
      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "popular-page-project-#{unique}-#{index}",
          name: "Popular Page Project #{index}",
          description: "Popular page project #{index}",
          organization_id: organization.id,
          visibility: "public"
        })
    end)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "popular-repositories-next"
  end

  test "includes favicon link in layout", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(rel="icon")
    assert html =~ ~s(href="/favicon.ico")
  end
end
