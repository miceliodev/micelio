defmodule MicelioWeb.Browser.PageController do
  use MicelioWeb, :controller

  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  def home(conn, params) do
    popular_page = parse_popular_page(params)
    popular_limit = 6
    popular_offset = (popular_page - 1) * popular_limit

    popular_repositories =
      case conn.assigns.current_user do
        %{} = user ->
          Repositories.list_recent_repositories_for_user(
            user,
            limit: popular_limit + 1,
            offset: popular_offset
          )

        _ ->
          Repositories.list_popular_repositories(
            limit: popular_limit + 1,
            offset: popular_offset,
            user: conn.assigns.current_user
          )
      end

    {popular_repositories, popular_has_more} =
      split_popular_repositories(popular_repositories, popular_limit)

    conn
    |> PageMeta.put(
      title_parts: [],
      description: "Micelio is a forge designed for agent-first development.",
      canonical_url: url(~p"/")
    )
    |> assign(:popular_repositories, popular_repositories)
    |> assign(:popular_page, popular_page)
    |> assign(:popular_has_more, popular_has_more)
    |> render(:home)
  end

  defp parse_popular_page(params) do
    case Integer.parse(Map.get(params, "popular_page", "1")) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp split_popular_repositories(repositories, limit) do
    if length(repositories) > limit do
      {Enum.take(repositories, limit), true}
    else
      {repositories, false}
    end
  end
end
