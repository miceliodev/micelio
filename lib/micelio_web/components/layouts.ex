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

  defp sidebar_active?(current_path, link_path) do
    if link_path == "/" do
      current_path == "/"
    else
      String.starts_with?(current_path, link_path)
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
  attr :repository_nav, :map, default: nil, doc: "optional repository navigation context"

  slot :breadcrumb, doc: "optional breadcrumb content shown in the navbar"
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
            aria-controls="sidebar"
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

        <%= if @breadcrumb != [] do %>
          <div class="navbar-breadcrumb">
            {render_slot(@breadcrumb)}
          </div>
        <% end %>

        <div class="navbar-end">
          <%= if assigns[:current_user] do %>
            <a
              href={~p"/account"}
              class="navbar-user-avatar"
              id="navbar-user"
              aria-label={
                gettext("Account (@%{handle})", handle: assigns.current_user.account.handle)
              }
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
          <% else %>
            <a href={~p"/auth/login"} class="navbar-cta">
              {gettext("Get started")}
            </a>
          <% end %>
        </div>
      </nav>
    </div>
    <.flash_group flash={@flash} />

    <div class="app-shell">
      <aside class="sidebar" id="sidebar" aria-label={gettext("Main navigation")}>
        <nav class="sidebar-nav">
          <div class="sidebar-section">
            <%= if @repository_nav do %>
              <% repository_base_path =
                @repository_nav[:base_path] ||
                  "/#{@repository_nav.account_handle}/#{@repository_nav.repository_handle}" %>
              <% prompt_requests_path = "#{repository_base_path}/prs" %>
              <% sessions_path = "#{repository_base_path}/sessions" %>
              <% settings_path = "#{repository_base_path}/settings" %>
              <% active_nav = @repository_nav[:active] %>
              <% prompt_requests_active =
                if active_nav do
                  active_nav == :prompt_requests
                else
                  sidebar_active?(@current_path, prompt_requests_path)
                end %>
              <% sessions_active =
                if active_nav do
                  active_nav == :sessions
                else
                  sidebar_active?(@current_path, sessions_path)
                end %>
              <% home_active =
                if active_nav do
                  active_nav == :home
                else
                  @current_path == repository_base_path
                end %>
              <% settings_active =
                if active_nav do
                  active_nav == :settings
                else
                  sidebar_active?(@current_path, settings_path)
                end %>
              <a
                href={repository_base_path}
                class={[
                  "sidebar-link",
                  home_active && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M5 12l-2 0l9-9l9 9l-2 0" />
                    <path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
                    <path d="M9 21v-6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v6" />
                  </svg>
                </span>
                {gettext("Home")}
              </a>
              <a
                href={prompt_requests_path}
                class={[
                  "sidebar-link",
                  prompt_requests_active && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M8 9h8" />
                    <path d="M8 13h6" />
                    <path d="M9 18h-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-3l-3 3-3-3z" />
                  </svg>
                </span>
                {gettext("Prompt requests")}
              </a>
              <a
                href={sessions_path}
                class={[
                  "sidebar-link",
                  sessions_active && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M12 8v4l3 3" />
                    <circle cx="12" cy="12" r="9" />
                  </svg>
                </span>
                {gettext("Sessions")}
              </a>
              <a
                :if={@repository_nav[:show_settings?]}
                href={settings_path}
                class={[
                  "sidebar-link",
                  settings_active && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 0 0 1.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 0 0-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 0 0-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 0 0-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 0 0-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 0 0 1.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                    <circle cx="12" cy="12" r="3" />
                  </svg>
                </span>
                {gettext("Settings")}
              </a>
            <% else %>
              <%= if assigns[:current_user] do %>
                <a
                  href={~p"/repositories"}
                  class={[
                    "sidebar-link",
                    sidebar_active?(@current_path, "/repositories") && "sidebar-link-active"
                  ]}
                >
                  <span class="sidebar-link-icon">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M5 4h4l3 3h7a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-11a2 2 0 0 1 2 -2" />
                    </svg>
                  </span>
                  {gettext("Repositories")}
                </a>
              <% end %>
              <a
                href={~p"/blog"}
                class={[
                  "sidebar-link",
                  sidebar_active?(@current_path, "/blog") && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M3 4m0 2a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2z" /><path d="M7 8h10" /><path d="M7 12h10" /><path d="M7 16h10" />
                  </svg>
                </span>
                {gettext("Blog")}
              </a>
              <a
                href={~p"/docs"}
                class={[
                  "sidebar-link",
                  sidebar_active?(@current_path, "/docs") && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M3 19a9 9 0 0 1 9 0a9 9 0 0 1 9 0" /><path d="M3 6a9 9 0 0 1 9 0a9 9 0 0 1 9 0" /><line
                      x1="3"
                      y1="6"
                      x2="3"
                      y2="19"
                    /><line x1="12" y1="6" x2="12" y2="19" /><line x1="21" y1="6" x2="21" y2="19" />
                  </svg>
                </span>
                {gettext("Docs")}
              </a>
              <a
                href={~p"/changelog"}
                class={[
                  "sidebar-link",
                  sidebar_active?(@current_path, "/changelog") && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="12 8 12 12 14 14" /><path d="M3.05 11a9 9 0 1 1 .5 4m-.5 5v-5h5" />
                  </svg>
                </span>
                {gettext("Changelog")}
              </a>
              <a
                href={~p"/search"}
                class={[
                  "sidebar-link",
                  sidebar_active?(@current_path, "/search") && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <circle cx="10" cy="10" r="7" /><line x1="21" y1="21" x2="15" y2="15" />
                  </svg>
                </span>
                {gettext("Search")}
              </a>
            <% end %>
          </div>

          <%= if assigns[:current_user] && !@repository_nav do %>
            <div class="sidebar-section">
              <a
                href={~p"/account"}
                class={[
                  "sidebar-link",
                  sidebar_active?(@current_path, "/account") && "sidebar-link-active"
                ]}
              >
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <circle cx="12" cy="7" r="4" /><path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2" />
                  </svg>
                </span>
                {gettext("Account")}
              </a>
              <%= if Micelio.Admin.admin_user?(assigns.current_user) do %>
                <a
                  href={~p"/admin"}
                  class={[
                    "sidebar-link",
                    sidebar_active?(@current_path, "/admin") && "sidebar-link-active"
                  ]}
                >
                  <span class="sidebar-link-icon">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M12 3a12 12 0 0 0 8.5 3a12 12 0 0 1 -8.5 15a12 12 0 0 1 -8.5 -15a12 12 0 0 0 8.5 -3" />
                    </svg>
                  </span>
                  {gettext("Admin")}
                </a>
              <% end %>
            </div>
          <% end %>
        </nav>

        <div class="sidebar-bottom">
          <%= if assigns[:current_user] do %>
            <form action={~p"/auth/logout"} method="post" class="sidebar-logout-form">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <input type="hidden" name="_method" value="delete" />
              <button type="submit" class="sidebar-logout-btn">
                <span class="sidebar-link-icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M14 8v-2a2 2 0 0 0 -2 -2h-7a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2 -2v-2" /><path d="M9 12h12l-3 -3" /><path d="M18 15l3 -3" />
                  </svg>
                </span>
                {gettext("Logout")}
              </button>
            </form>
          <% else %>
            <a href={~p"/auth/login"} class="sidebar-link">
              <span class="sidebar-link-icon">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M9 12h12l-3 -3" /><path d="M18 15l3 -3" /><path d="M14 8v-2a2 2 0 0 0 -2 -2h-7a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2 -2v-2" />
                </svg>
              </span>
              {gettext("Get started")}
            </a>
          <% end %>

          <button
            id="theme-toggle"
            type="button"
            class="sidebar-logout-btn"
            aria-label={gettext("Toggle theme")}
          >
            <span class="sidebar-link-icon">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" /><path d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7" />
              </svg>
            </span>
            <span id="theme-toggle-text">{gettext("Theme")}</span>
          </button>
        </div>
      </aside>
      <div id="sidebar-backdrop" class="sidebar-backdrop"></div>

      <div class="app-main">
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

              <div class="site-footer-meta">
                © {Date.utc_today().year} Micelio
              </div>
            </div>
          </div>
        </footer>
      </div>
    </div>
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
