defmodule MicelioWeb.Router do
  use MicelioWeb, :router

  @api_rate_limit Application.compile_env(:micelio, :api_rate_limit, [])
  @api_rate_limit_limit Keyword.get(@api_rate_limit, :limit, 100)
  @api_rate_limit_window_ms Keyword.get(@api_rate_limit, :window_ms, 60_000)
  @api_rate_limit_authenticated_limit Keyword.get(@api_rate_limit, :authenticated_limit, 500)
  @api_rate_limit_authenticated_window_ms Keyword.get(
                                            @api_rate_limit,
                                            :authenticated_window_ms,
                                            @api_rate_limit_window_ms
                                          )
  @api_rate_limit_abuse_threshold Keyword.get(@api_rate_limit, :abuse_threshold, 5)
  @api_rate_limit_abuse_window_ms Keyword.get(@api_rate_limit, :abuse_window_ms, 300_000)
  @api_rate_limit_abuse_block_ms Keyword.get(@api_rate_limit, :abuse_block_ms, 3_600_000)

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {MicelioWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(MicelioWeb.Plugs.OpenGraphCacheBuster)
    plug(MicelioWeb.LocalePlug)
    plug(MicelioWeb.AuthenticationPlug)
    plug(MicelioWeb.Plugs.RateLimitPlug, limit: 200, window_ms: 60_000, bucket_prefix: "browser")
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(MicelioWeb.Plugs.ApiAuthenticationPlug)

    plug(MicelioWeb.Plugs.RateLimitPlug,
      limit: @api_rate_limit_limit,
      window_ms: @api_rate_limit_window_ms,
      bucket_prefix: "api",
      authenticated_limit: @api_rate_limit_authenticated_limit,
      authenticated_window_ms: @api_rate_limit_authenticated_window_ms,
      abuse_threshold: @api_rate_limit_abuse_threshold,
      abuse_window_ms: @api_rate_limit_abuse_window_ms,
      abuse_block_ms: @api_rate_limit_abuse_block_ms
    )
  end

  pipeline :api_stream do
    plug(:accepts, ["json", "event-stream"])
    plug(MicelioWeb.Plugs.ApiAuthenticationPlug)

    plug(MicelioWeb.Plugs.RateLimitPlug,
      limit: @api_rate_limit_limit,
      window_ms: @api_rate_limit_window_ms,
      bucket_prefix: "api",
      authenticated_limit: @api_rate_limit_authenticated_limit,
      authenticated_window_ms: @api_rate_limit_authenticated_window_ms,
      abuse_threshold: @api_rate_limit_abuse_threshold,
      abuse_window_ms: @api_rate_limit_abuse_window_ms,
      abuse_block_ms: @api_rate_limit_abuse_block_ms
    )
  end

  pipeline :api_docs do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: MicelioWeb.ApiSpec)
  end

  pipeline :activity_pub do
    plug(:accepts, ["json"])
  end

  pipeline :require_auth do
    plug(MicelioWeb.RequireAuthPlug)
  end

  pipeline :require_admin do
    plug(MicelioWeb.RequireAdminPlug)
  end

  pipeline :load_resources do
    plug(MicelioWeb.ResourcePlug, :load_account)
    plug(MicelioWeb.ResourcePlug, :load_repository)
  end

  pipeline :forge_resources do
    plug(MicelioWeb.Plugs.ForgeResourcePlug)
  end

  pipeline :og_image do
    plug(:put_secure_browser_headers)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:micelio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/admin" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: MicelioWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  # Sandbox module serving (authenticated via per-sandbox tokens)
  pipeline :sandbox_modules do
    plug(MicelioWeb.Plugs.SandboxTokenPlug)
  end

  scope "/sandbox/modules", MicelioWeb do
    pipe_through(:sandbox_modules)

    get("/*path", SandboxModuleController, :show)
  end

  # Blog routes (public)
  scope "/blog", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/", BlogController, :index)
    get("/rss", BlogController, :rss)
    get("/atom", BlogController, :atom)
    get("/:id", BlogController, :show)
  end

  # Docs routes (public)
  scope "/docs", MicelioWeb do
    pipe_through(:browser)

    live_session :docs,
      on_mount: [{MicelioWeb.LiveAuth, :current_user}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/", DocsLive.Index, :index)
    end
  end

  scope "/docs", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/cli-reference", DocsController, :cli_reference)
    get("/:category", DocsController, :category)
    get("/:category/:id", DocsController, :show)
  end

  # API try-it proxy (session-authenticated, for interactive docs)
  scope "/api-try", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth])

    post("/", ApiTryController, :proxy)
  end

  # Changelog routes (public)
  scope "/changelog", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/", ChangelogController, :index)
    get("/rss", ChangelogController, :rss)
    get("/atom", ChangelogController, :atom)
    get("/category/:category", ChangelogController, :category)
    get("/version/:version", ChangelogController, :version)
    get("/:id", ChangelogController, :show)
  end

  # Forge about proxy (internal, consumed by page JS)
  scope "/forge-about", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/:host/:owner/:repo", ForgeAboutController, :show)
  end

  # Auth routes (before catch-all)
  scope "/auth", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/login", AuthController, :new)
    get("/dev/seed", AuthController, :dev_seed)
    post("/passkey/options", PasskeyController, :authentication_options)
    post("/passkey/authenticate", PasskeyController, :authenticate)
    get("/github", AuthController, :github_start)
    get("/github/callback", AuthController, :github_callback)
    get("/gitlab", AuthController, :gitlab_start)
    get("/gitlab/callback", AuthController, :gitlab_callback)
    post("/login", AuthController, :create)
    get("/sent", AuthController, :sent)
    get("/verify/:token", AuthController, :verify)
    get("/totp", TotpController, :new)
    post("/totp", TotpController, :create)
    delete("/logout", AuthController, :delete)
  end

  scope "/auth", MicelioWeb.Oauth do
    pipe_through(:api)

    post("/device", DeviceController, :create)
  end

  scope "/api" do
    pipe_through(:api_docs)

    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
    get("/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")
  end

  scope "/api", MicelioWeb.Api.V1 do
    pipe_through(:api)

    # Organizations
    get("/orgs", OrganizationController, :index)
    get("/orgs/:handle", OrganizationController, :show)

    # Repositories
    get("/orgs/:org/repositories", RepositoryController, :index)
    post("/orgs/:org/repositories", RepositoryController, :create)
    get("/orgs/:org/repositories/:handle", RepositoryController, :show)
    patch("/orgs/:org/repositories/:handle", RepositoryController, :update)
    delete("/orgs/:org/repositories/:handle", RepositoryController, :delete)

    # Sessions
    get("/orgs/:org/repositories/:repo/sessions", SessionController, :index)
    post("/orgs/:org/repositories/:repo/sessions", SessionController, :create)
    get("/sessions/:session_id", SessionController, :show)
    post("/sessions/:session_id/land", SessionController, :land)

    # Plans
    get("/orgs/:org/repositories/:repo/plans", PlanController, :index)
    post("/orgs/:org/repositories/:repo/plans", PlanController, :create)

    get("/orgs/:org/repositories/:repo/plans/:number", PlanController, :show)

    patch(
      "/orgs/:org/repositories/:repo/plans/:number",
      PlanController,
      :update
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/close",
      PlanController,
      :close
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/reopen",
      PlanController,
      :reopen
    )

    get(
      "/orgs/:org/repositories/:repo/plans/:number/comments",
      PlanController,
      :comments_index
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/comments",
      PlanController,
      :comments_create
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/session/start",
      PlanController,
      :start_session
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/session/stop",
      PlanController,
      :stop_session
    )

    post(
      "/orgs/:org/repositories/:repo/plans/:number/session/messages",
      PlanController,
      :send_session_message
    )

    # Content
    get("/orgs/:org/repositories/:repo/tree", ContentController, :tree)
    get("/orgs/:org/repositories/:repo/blob/*path", ContentController, :blob)
    get("/orgs/:org/repositories/:repo/blame/*path", ContentController, :blame)
  end

  scope "/api/mobile", MicelioWeb.Api.Mobile do
    pipe_through(:api)

    get("/repositories", RepositoryController, :index)
    get("/repositories/:organization_handle/:repository_handle", RepositoryController, :show)
  end

  scope "/api/remote-executions", MicelioWeb.Api do
    pipe_through(:api)

    post("/", RemoteExecutionController, :create)
    get("/:id", RemoteExecutionController, :show)
  end

  scope "/api/repositories", MicelioWeb.Api do
    pipe_through(:api)

    get("/:organization_handle/:repository_handle/token-pool", TokenPoolController, :show)
    patch("/:organization_handle/:repository_handle/token-pool", TokenPoolController, :update)

    post(
      "/:organization_handle/:repository_handle/token-contributions",
      TokenContributionController,
      :create
    )

    post(
      "/:organization_handle/:repository_handle/plans",
      PlanController,
      :create
    )
  end

  scope "/api/sessions", MicelioWeb.Api do
    pipe_through(:api_stream)

    get("/:id/events/stream", SessionEventController, :stream)
  end

  scope "/.well-known", MicelioWeb do
    pipe_through(:activity_pub)

    get("/micelio.json", WellKnownController, :micelio)
    get("/webfinger", ActivityPubController, :webfinger)
  end

  scope "/ap", MicelioWeb do
    pipe_through(:activity_pub)

    get("/actors/:handle", ActivityPubController, :actor)
    get("/profiles/:handle", ActivityPubController, :profile)
    get("/repositories/:account/:repository", ActivityPubController, :repository)
    get("/actors/:handle/outbox", ActivityPubController, :outbox)
    post("/actors/:handle/inbox", ActivityPubController, :inbox)
    get("/actors/:handle/followers", ActivityPubController, :followers)
    get("/actors/:handle/following", ActivityPubController, :following)
  end

  scope "/oauth", MicelioWeb.Oauth do
    pipe_through(:browser)

    get("/authorize", AuthorizeController, :authorize)
  end

  scope "/oauth", MicelioWeb.Oauth do
    pipe_through(:api)

    post("/register", RegistrationController, :register)
    post("/token", TokenController, :token)
  end

  scope "/device", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth])

    get("/auth", DeviceAuthController, :new)
    post("/auth/verify", DeviceAuthController, :verify)
  end

  # Redirect legacy /projects URLs to new paths
  scope "/projects", MicelioWeb.Browser do
    pipe_through(:browser)

    get("/", RedirectController, :projects_index)
    get("/new", RedirectController, :projects_new)
    get("/:account/:repository", RedirectController, :projects_show)
    get("/:account/:repository/edit", RedirectController, :projects_edit)
    get("/:account/:repository/sessions", RedirectController, :projects_sessions)
    get("/:account/:repository/sessions/:id", RedirectController, :projects_session)
    get("/:account/:repository/prompt-requests", RedirectController, :projects_plans)

    get(
      "/:account/:repository/prompt-requests/new",
      RedirectController,
      :projects_plan_new
    )

    get("/:account/:repository/prompt-requests/:id", RedirectController, :projects_plan)
  end

  # Repository list routes (require authentication)
  scope "/repositories", MicelioWeb do
    pipe_through([:browser, :require_auth])

    live_session :repositories,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/", RepositoryLive.Index, :index)
      live("/new", RepositoryLive.New, :new)
    end
  end

  # Forge per-repository routes
  for forge <- ["github.com", "gitlab.com"] do
    scope "/", MicelioWeb do
      pipe_through([:browser, :require_auth, :forge_resources])

      live_session :"forge_#{String.replace(forge, ".", "_")}_management",
        on_mount: [
          {MicelioWeb.ForgeMount, forge},
          {MicelioWeb.LiveAuth, :require_auth},
          MicelioWeb.LiveOpenGraphCacheBuster
        ] do
        live("/#{forge}/:owner/:repo/edit", RepositoryLive.Edit, :edit)
        live("/#{forge}/:owner/:repo/sessions", SessionLive.Index, :index)
        live("/#{forge}/:owner/:repo/sessions/:id", SessionLive.Show, :show)
        live("/#{forge}/:owner/:repo/prs/new", PlanLive.New, :new)
        live("/#{forge}/:owner/:repo/prs/:number/edit", PlanLive.Edit, :edit)
      end
    end

    scope "/", MicelioWeb do
      pipe_through([:browser, :require_auth, :forge_resources])

      live_session :"forge_#{String.replace(forge, ".", "_")}_settings",
        on_mount: [
          {MicelioWeb.ForgeMount, forge},
          {MicelioWeb.LiveAuth, :require_auth},
          MicelioWeb.LiveOpenGraphCacheBuster
        ] do
        live("/#{forge}/:owner/:repo/settings", RepositoryLive.Settings, :edit)
        live("/#{forge}/:owner/:repo/settings/webhooks", RepositoryLive.Webhooks, :index)
      end
    end

    scope "/", MicelioWeb do
      pipe_through([:browser, :forge_resources])

      live_session :"forge_#{String.replace(forge, ".", "_")}_public",
        on_mount: [
          {MicelioWeb.ForgeMount, forge},
          {MicelioWeb.LiveAuth, :current_user},
          MicelioWeb.LiveOpenGraphCacheBuster
        ] do
        live("/#{forge}/:owner/:repo/agents", AgentLive.Index, :index)
        live("/#{forge}/:owner/:repo/prs", PlanLive.Index, :index)
        live("/#{forge}/:owner/:repo/prs/:number", PlanLive.Show, :show)
      end
    end

    scope "/", MicelioWeb.Browser do
      pipe_through([:browser, :require_auth, :forge_resources])

      post(
        "/#{forge}/:owner/:repo/token-contributions",
        RepositoryController,
        :contribute_tokens
      )
    end
  end

  # Per-repository routes (require authentication)
  scope "/", MicelioWeb do
    pipe_through([:browser, :require_auth, :load_resources])

    live_session :repository_management,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/:account/:repository/edit", RepositoryLive.Edit, :edit)
      live("/:account/:repository/sessions", SessionLive.Index, :index)
      live("/:account/:repository/sessions/:id", SessionLive.Show, :show)
      live("/:account/:repository/prs/new", PlanLive.New, :new)
      live("/:account/:repository/prs/:number/edit", PlanLive.Edit, :edit)
    end
  end

  # Organization routes (require authentication)
  scope "/organizations", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth])

    get("/new", OrganizationController, :new)
    post("/", OrganizationController, :create)
  end

  scope "/organizations", MicelioWeb do
    pipe_through([:browser, :require_auth])

    live_session :organization_settings,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/:organization_handle/settings", OrganizationLive.Settings, :edit)
    end
  end

  # Admin routes (require admin access)
  scope "/admin", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth, :require_admin])

    get("/", AdminController, :index)
    get("/usage", AdminController, :usage)
  end

  scope "/admin", MicelioWeb do
    pipe_through([:browser, :require_auth, :require_admin])

    live_session :admin,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/prompts", AdminPromptRegistryLive.Index, :index)
      live("/prompt-templates", AdminPlanTemplatesLive.Index, :index)
      live("/errors", AdminErrorsLive.Index, :index)
      live("/errors/settings", AdminErrorNotificationsLive.Index, :index)
      live("/errors/:id", AdminErrorsLive.Show, :show)
    end
  end

  scope "/settings", MicelioWeb do
    pipe_through([:browser, :require_auth])

    live_session :account_settings,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/storage", StorageSettingsLive, :edit)
    end
  end

  scope "/account", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth])

    get("/", ProfileController, :show)
    patch("/profile", ProfileController, :update)
    patch("/storage/s3", ProfileController, :update_s3)
    post("/passkeys/options", PasskeyController, :registration_options)
    post("/passkeys", PasskeyController, :register)
    delete("/passkeys/:id", PasskeyController, :delete)
    post("/totp/start", TotpController, :start)
    post("/totp/verify", TotpController, :verify)
    post("/totp/cancel", TotpController, :cancel)
    post("/totp/disable", TotpController, :disable)
    get("/devices", DeviceController, :index)
    delete("/devices/:id", DeviceController, :delete)
  end

  scope "/", MicelioWeb do
    pipe_through([:browser, :require_auth, :load_resources])

    live_session :repository_settings,
      on_mount: [{MicelioWeb.LiveAuth, :require_auth}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/:account/:repository/settings", RepositoryLive.Settings, :edit)
      live("/:account/:repository/settings/webhooks", RepositoryLive.Webhooks, :index)
    end
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :require_auth, :load_resources])

    post("/:account/:repository/token-contributions", RepositoryController, :contribute_tokens)
  end

  scope "/og", MicelioWeb.Browser do
    pipe_through(:og_image)

    get("/:hash", OpenGraphImageController, :show)
  end

  scope "/", MicelioWeb do
    pipe_through([:browser, :load_resources])

    live_session :public,
      on_mount: [{MicelioWeb.LiveAuth, :current_user}, MicelioWeb.LiveOpenGraphCacheBuster] do
      live("/:account/:repository/agents", AgentLive.Index, :index)
      live("/:account/:repository/prs", PlanLive.Index, :index)
      live("/:account/:repository/prs/:number", PlanLive.Show, :show)
    end
  end

  # Redirect old /prompt-requests URLs to /prs
  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get("/:account/:repository/prompt-requests", RedirectController, :projects_plans)

    get(
      "/:account/:repository/prompt-requests/new",
      RedirectController,
      :projects_plan_new
    )

    get("/:account/:repository/prompt-requests/:id", RedirectController, :projects_plan)
  end

  # Locale-prefixed marketing routes (for SEO and explicit locale selection)
  for locale <- ~w(ko zh_CN zh_TW ja) do
    scope "/#{locale}", MicelioWeb.Browser do
      pipe_through([:browser])

      get("/", PageController, :home)
      get("/privacy", LegalController, :privacy)
      get("/terms", LegalController, :terms)
      get("/cookies", LegalController, :cookies)
      get("/impressum", LegalController, :impressum)
    end
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get("/", PageController, :home)

    get("/privacy", LegalController, :privacy)
    get("/terms", LegalController, :terms)
    get("/cookies", LegalController, :cookies)
    get("/impressum", LegalController, :impressum)
    get("/search", SearchController, :index)
  end

  # Forge URLs served directly (controller routes)
  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :forge_resources])

    get("/github.com/:owner/:repo", RepositoryController, :show)
    get("/github.com/:owner/:repo/tree/*path", RepositoryController, :tree)
    get("/github.com/:owner/:repo/blob/*path", RepositoryController, :blob)
    get("/github.com/:owner/:repo/blame/*path", RepositoryController, :blame)

    get("/gitlab.com/:owner/:repo", RepositoryController, :show)
    get("/gitlab.com/:owner/:repo/tree/*path", RepositoryController, :tree)
    get("/gitlab.com/:owner/:repo/blob/*path", RepositoryController, :blob)
    get("/gitlab.com/:owner/:repo/blame/*path", RepositoryController, :blame)
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get("/:account", AccountController, :show)
    get("/:account/:repository/badge.svg", RepositoryController, :badge)
    get("/:account/:repository/tree/*path", RepositoryController, :tree)
    get("/:account/:repository/blob/*path", RepositoryController, :blob)
    get("/:account/:repository/blame/*path", RepositoryController, :blame)
    get("/:account/:repository", RepositoryController, :show)
  end
end
