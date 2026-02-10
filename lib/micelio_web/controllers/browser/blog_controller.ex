defmodule MicelioWeb.Browser.BlogController do
  use MicelioWeb, :controller

  alias Micelio.Blog
  alias Micelio.Blog.People
  alias MicelioWeb.PageMeta

  def index(conn, _params) do
    locale = conn.assigns[:locale] || "en"

    conn
    |> PageMeta.put(
      title_parts: ["Blog"],
      description:
        "Updates and insights from the Micelio team about building the future of agent-first software development.",
      canonical_url: url(~p"/blog")
    )
    |> render(:index, posts: Blog.all_posts(locale))
  end

  def show(conn, %{"id" => id}) do
    locale = conn.assigns[:locale] || "en"
    post = Blog.get_post_by_id!(id, locale)
    author = People.get!(post.author)

    conn
    |> PageMeta.put(
      title_parts: [post.title, "Blog"],
      description: post.description,
      canonical_url: url(~p"/blog/#{post.id}"),
      type: "article",
      author: author,
      open_graph: %{
        "article:published_time" => Date.to_iso8601(post.date),
        "article:author" => author.name
      }
    )
    |> render(:show, post: post)
  end

  def rss(conn, _params) do
    # RSS feeds are always in English (default)
    posts = Blog.recent_posts(10, "en")

    conn
    |> put_resp_content_type("application/rss+xml")
    |> render(:rss, posts: posts, layout: false)
  end

  def atom(conn, _params) do
    # Atom feeds are always in English (default)
    posts = Blog.recent_posts(10, "en")

    conn
    |> put_resp_content_type("application/atom+xml")
    |> render(:atom, posts: posts, layout: false)
  end
end
