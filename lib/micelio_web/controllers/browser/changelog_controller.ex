defmodule MicelioWeb.Browser.ChangelogController do
  use MicelioWeb, :controller

  alias Micelio.Changelog
  alias MicelioWeb.PageMeta

  def index(conn, _params) do
    entries = Changelog.all_entries()
    categories = Changelog.all_categories()
    versions = Changelog.all_versions()

    conn
    |> PageMeta.put(
      title_parts: ["Changelog"],
      description:
        "Stay up to date with the latest changes, improvements, and new features in Micelio.",
      canonical_url: url(~p"/changelog")
    )
    |> assign(:entries, entries)
    |> assign(:categories, categories)
    |> assign(:versions, versions)
    |> render(:index)
  end

  def show(conn, %{"id" => id}) do
    entry = Changelog.get_entry_by_id!(id)

    conn
    |> PageMeta.put(
      title_parts: [entry.title, "Changelog"],
      description: entry.description,
      canonical_url: url(~p"/changelog/#{entry.id}"),
      type: "article",
      open_graph: %{"article:published_time" => Date.to_iso8601(entry.date)}
    )
    |> assign(:entry, entry)
    |> render(:show)
  end

  def version(conn, %{"version" => version}) do
    entries = Changelog.get_entries_by_version!(version)

    conn
    |> PageMeta.put(
      title_parts: ["Version #{version}", "Changelog"],
      description: "All changes included in version #{version}.",
      canonical_url: url(~p"/changelog/version/#{version}")
    )
    |> assign(:entries, entries)
    |> assign(:version, version)
    |> render(:version)
  end

  def category(conn, %{"category" => category}) do
    entries = Changelog.get_entries_by_category!(category)
    categories = Changelog.all_categories()
    category_label = String.capitalize(category)

    conn
    |> PageMeta.put(
      title_parts: [category_label, "Changelog"],
      description: "Changelog entries in the #{category_label} category.",
      canonical_url: url(~p"/changelog/category/#{category}")
    )
    |> assign(:entries, entries)
    |> assign(:category, category)
    |> assign(:categories, categories)
    |> render(:category)
  end

  def rss(conn, _params) do
    entries = Changelog.recent_entries(20)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> render(:rss, entries: entries, layout: false)
  end

  def atom(conn, _params) do
    entries = Changelog.recent_entries(20)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> render(:atom, entries: entries, layout: false)
  end
end
