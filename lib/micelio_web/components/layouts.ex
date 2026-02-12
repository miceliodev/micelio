defmodule MicelioWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MicelioWeb, :html
  use Gettext, backend: MicelioWeb.Gettext

  @non_english_locales ~w(ko zh_CN zh_TW ja)

  # Helper to build locale-aware paths for marketing pages
  defp locale_path(assigns, path) do
    locale = assigns[:locale] || "en"

    if locale in @non_english_locales do
      "/#{locale}#{path}"
    else
      path
    end
  end

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map,
    default: nil,
    doc: "the current authenticated user"

  attr :locale, :string, default: "en", doc: "the current locale"
  attr :current_path, :string, default: "/", doc: "the current path without locale prefix"
  attr :page_class, :string, default: nil, doc: "optional page-level layout class"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="navbar-wrapper">
      <nav class="navbar" aria-label="Primary">
        <div class="navbar-start">
          <button
            type="button"
            class="navbar-hamburger"
            id="navbar-hamburger"
            aria-expanded="false"
            aria-controls="navbar-menu"
            aria-label={gettext("Toggle navigation")}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <line x1="4" x2="20" y1="6" y2="6" />
              <line x1="4" x2="20" y1="12" y2="12" />
              <line x1="4" x2="20" y1="18" y2="18" />
            </svg>
          </button>
          <span class="brand">
            <span class="icon">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
                <path d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm0 448c-110.5 0-200-89.5-200-200S145.5 56 256 56s200 89.5 200 200-89.5 200-200 200z" />
              </svg>
            </span>
            <a href="/">micelio</a>
          </span>
        </div>

        <div class="navbar-menu" id="navbar-menu">
          <%= if assigns[:current_user] do %>
            <a href={~p"/repositories"}>{gettext("repositories")}</a>
          <% end %>
          <a href={~p"/blog"}>{gettext("blog")}</a>
          <a href={~p"/docs"}>{gettext("docs")}</a>
          <a href={~p"/changelog"}>{gettext("changelog")}</a>
          <a href={~p"/search"}>{gettext("search")}</a>

          <div class="navbar-spacer"></div>

          <%= if assigns[:current_user] do %>
            <%= if Micelio.Admin.admin_user?(assigns.current_user) do %>
              <a href={~p"/admin"}>{gettext("admin")}</a>
            <% end %>
            <form action={~p"/auth/logout"} method="post" class="navbar-logout-form">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <input type="hidden" name="_method" value="delete" />
              <button type="submit" class="navbar-link-button">{gettext("logout")}</button>
            </form>
          <% else %>
            <a href={~p"/auth/login"} class="navbar-cta">
              {gettext("Get started")}
              <span class="icon">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 512">
                  <path d="M0 384.662V127.338c0-17.818 21.543-26.741 34.142-14.142l128.662 128.662c7.81 7.81 7.81 20.474 0 28.284L34.142 398.804C21.543 411.404 0 402.48 0 384.662z" />
                </svg>
              </span>
            </a>
          <% end %>
        </div>

        <%= if assigns[:current_user] do %>
          <a
            href={~p"/account"}
            class="navbar-user-avatar"
            id="navbar-user"
            aria-label={gettext("Account (@%{handle})", handle: assigns.current_user.account.handle)}
            title={"@#{assigns.current_user.account.handle}"}
          >
            <img
              src={gravatar_url(assigns.current_user.email)}
              width="24"
              height="24"
              alt=""
              loading="lazy"
              decoding="async"
              referrerpolicy="no-referrer"
            />
          </a>
        <% end %>
      </nav>
    </div>
    <.flash_group flash={@flash} />

    <main class={["page-main", @page_class]}>
      <div class={["page-content", @page_class]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <footer class="site-footer" id="site-footer">
      <div class="site-footer-content">
        <nav class="site-footer-nav" aria-label={gettext("Legal")}>
          <a href={locale_path(assigns, "/terms")}>{gettext("terms")}</a>
          <a href={locale_path(assigns, "/privacy")}>{gettext("privacy")}</a>
          <a href={locale_path(assigns, "/cookies")}>{gettext("cookies")}</a>
          <a href={locale_path(assigns, "/impressum")}>{gettext("impressum")}</a>
        </nav>

        <div class="site-footer-meta-group">
          <div class="site-footer-locale">
            <.language_selector
              current_locale={@locale}
              current_path={@current_path}
            />
          </div>

          <button
            id="theme-toggle"
            type="button"
            class="footer-theme-toggle"
            aria-label={gettext("Toggle theme")}
          >
            {gettext("theme")}
          </button>

          <div class="site-footer-meta">
            © {Date.utc_today().year} Micelio
          </div>
        </div>
      </div>
    </footer>
    """
  end

  # Using imported gravatar_url from CoreComponents

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-stack" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end
end
