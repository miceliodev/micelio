defmodule MicelioWeb.Browser.SearchController do
  use MicelioWeb, :controller

  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  def index(conn, params) do
    query = params["q"] || ""
    query = String.trim(query)

    results =
      if query == "" do
        []
      else
        Repositories.search_repositories(query, user: conn.assigns[:current_user])
      end

    conn
    |> PageMeta.put(
      title_parts: ["Search"],
      description: "Search repositories by name and description.",
      canonical_url: url(~p"/search")
    )
    |> assign(:query, query)
    |> assign(:results, results)
    |> assign(:form, Phoenix.Component.to_form(%{"q" => query}))
    |> render(:index)
  end
end
