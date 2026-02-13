defmodule MicelioWeb.Browser.DocsController do
  use MicelioWeb, :controller

  alias Micelio.CliReference
  alias Micelio.Docs
  alias MicelioWeb.DocsI18n
  alias MicelioWeb.PageMeta

  @doc """
  Renders the CLI reference documentation.
  """
  def cli_reference(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: [gettext("CLI Reference"), gettext("Docs")],
      description:
        gettext("Complete reference documentation for the mic command-line interface."),
      canonical_url: url(~p"/docs/cli-reference")
    )
    |> render(:cli_reference,
      docs: CliReference.docs(),
      commands_by_category: CliReference.commands_by_category()
    )
  end

  def category(conn, %{"category" => category}) do
    category_info = Docs.get_category(category)
    translated_category_info = DocsI18n.translate_category_info(category_info)

    if translated_category_info do
      pages = Docs.pages_by_category(category)

      conn
      |> PageMeta.put(
        title_parts: [translated_category_info.title, gettext("docs")],
        description: translated_category_info.description,
        canonical_url: url(~p"/docs/#{category}")
      )
      |> render(:category,
        category: category,
        category_info: translated_category_info,
        pages: pages
      )
    else
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  def show(conn, %{"category" => category, "id" => id}) do
    category_info = Docs.get_category(category)
    translated_category_info = DocsI18n.translate_category_info(category_info)

    if translated_category_info do
      page = Docs.get_page!(category, id)
      pages = Docs.pages_by_category(category)
      toc = Micelio.Docs.HtmlConverter.extract_toc(page.body)

      conn
      |> PageMeta.put(
        title_parts: [page.title, translated_category_info.title, gettext("docs")],
        description: page.description,
        canonical_url: url(~p"/docs/#{category}/#{id}")
      )
      |> render(:show,
        page: page,
        category: category,
        category_info: translated_category_info,
        pages: pages,
        toc: toc,
        api_try_authenticated: conn.assigns[:current_user] != nil
      )
    else
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
    end
  rescue
    _ ->
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
  end
end
