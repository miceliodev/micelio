defmodule MicelioWeb.DocsLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Docs
  alias Micelio.Docs.HtmlConverter
  alias MicelioWeb.DocsI18n
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"category" => category, "id" => id}, _uri, socket) do
    category_info = Docs.get_category(category)
    translated_category_info = DocsI18n.translate_category_info(category_info)

    if translated_category_info do
      page = Docs.get_page!(category, id)
      pages = Docs.pages_by_category(category)
      toc = HtmlConverter.extract_toc(page.body)

      socket =
        socket
        |> PageMeta.assign(
          title_parts: [page.title, translated_category_info.title, gettext("docs")],
          description: page.description,
          canonical_url: url(~p"/docs/#{category}/#{id}")
        )
        |> assign(
          page: page,
          category: category,
          category_info: translated_category_info,
          pages: pages,
          toc: toc,
          api_try_authenticated: socket.assigns[:current_user] != nil
        )

      {:noreply, socket}
    else
      {:noreply, push_navigate(socket, to: ~p"/docs")}
    end
  rescue
    _ ->
      {:noreply, push_navigate(socket, to: ~p"/docs")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="docs-container docs-show">
      <aside class="docs-sidebar">
        <h4 class="docs-sidebar-title">{@category_info.title}</h4>
        <nav class="docs-sidebar-nav" aria-label={gettext("Category pages")}>
          <a
            :for={page <- @pages}
            href={~p"/docs/#{@category}/#{page.id}"}
            class={["docs-sidebar-link", page.id == @page.id && "docs-sidebar-link-active"]}
          >
            {page.title}
          </a>
        </nav>
        <nav
          :if={@toc != []}
          class="docs-sidebar-toc"
          id="docs-toc"
          phx-hook=".DocsTocScrollSpy"
          phx-update="ignore"
          aria-label={gettext("On this page")}
        >
          <h4 class="docs-sidebar-toc-title">{gettext("On this page")}</h4>
          <a
            :for={entry <- @toc}
            href={"##{entry.id}"}
            class={["docs-sidebar-toc-link", entry.level == 3 && "docs-sidebar-toc-link-nested"]}
          >
            {entry.text}
          </a>
        </nav>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".DocsTocScrollSpy">
          export default {
            mounted() {
              const nav = this.el;
              const links = nav.querySelectorAll("a[href^='#']");
              const headings = Array.from(links)
                .map(a => document.getElementById(a.getAttribute("href").slice(1)))
                .filter(Boolean);
              if (headings.length === 0) return;

              const update = () => {
                const scrollY = window.scrollY + 100;
                let current = null;
                for (let i = headings.length - 1; i >= 0; i--) {
                  if (headings[i].offsetTop <= scrollY) {
                    current = headings[i];
                    break;
                  }
                }
                links.forEach(a => a.classList.remove("docs-sidebar-toc-link-active"));
                if (current) {
                  const active = nav.querySelector(`a[href="#${current.id}"]`);
                  if (active) active.classList.add("docs-sidebar-toc-link-active");
                }
              };

              window.addEventListener("scroll", update, { passive: true });
              update();
              this._scrollHandler = update;
            },
            destroyed() {
              if (this._scrollHandler) {
                window.removeEventListener("scroll", this._scrollHandler);
              }
            }
          }
        </script>
        <div class="docs-sidebar-back">
          <a href={~p"/docs"}>{gettext("All documentation")}</a>
        </div>
      </aside>

      <article class="docs-content">
        <nav class="docs-breadcrumb" aria-label={gettext("Breadcrumb")}>
          <a href={~p"/docs"}>{gettext("Documentation")}</a>
          <span class="docs-breadcrumb-separator">/</span>
          <a href={~p"/docs/#{@category}"}>{@category_info.title}</a>
          <span class="docs-breadcrumb-separator">/</span>
          <span class="docs-breadcrumb-current">{@page.title}</span>
        </nav>

        <.header>
          {@page.title}
          <:subtitle>
            {@page.description}
          </:subtitle>
        </.header>

        <.collapsible_toc toc={@toc} />

        <div
          class="docs-page-content prose"
          data-api-try-auth={to_string(@api_try_authenticated)}
        >
          {raw(@page.body)}
        </div>
        <div
          id="api-try-i18n"
          hidden
          data-sign-in-label={gettext("Sign in to try this")}
          data-send-label={gettext("Send request")}
          data-sending-label={gettext("Sending...")}
        >
        </div>
      </article>
    </div>
    """
  end
end
