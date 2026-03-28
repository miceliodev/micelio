defmodule Micelio.Handles do
  @moduledoc """
  Reserved handles that cannot be used by accounts.
  Based on GitHub and GitLab reserved username patterns.
  """

  @reserved [
    # Navigation and routes
    "settings",
    "admin",
    "api",
    "auth",
    "login",
    "logout",
    "signup",
    "register",
    "signin",
    "signout",
    "sign-in",
    "sign-out",
    "sign-up",

    # Static pages
    "help",
    "about",
    "contact",
    "legal",
    "terms",
    "privacy",
    "features",
    "security",
    "status",
    "blog",
    "press",
    "jobs",
    "careers",

    # Explore and discovery
    "explore",
    "search",
    "discover",
    "trending",
    "topics",
    "collections",

    # CRUD actions
    "new",
    "edit",
    "delete",
    "create",
    "update",
    "remove",
    "destroy",

    # Resources
    "users",
    "user",
    "orgs",
    "org",
    "organizations",
    "organization",
    "teams",
    "team",
    "repositories",
    "project",
    "repositories",
    "repository",
    "repos",
    "repo",
    "gists",
    "gist",
    "issues",
    "pulls",
    "pull",
    "commits",
    "commit",
    "branches",
    "branch",
    "tags",
    "releases",
    "actions",
    "workflows",
    "packages",
    "marketplace",
    "sponsors",
    "notifications",
    "stars",
    "watching",
    "followers",
    "following",

    # Dashboard and account
    "dashboard",
    "profile",
    "account",
    "billing",
    "subscription",
    "plan",
    "plans",

    # Developer resources
    "docs",
    "documentation",
    "developer",
    "developers",
    "apps",
    "oauth",
    "integrations",
    "webhooks",
    "tokens",

    # System and special
    "root",
    "www",
    "mail",
    "email",
    "ftp",
    "ssh",
    "assets",
    "static",
    "public",
    "raw",
    "blob",
    "tree",
    "compare",
    "diff",
    "files",
    "archive",
    "download",
    "uploads",
    "media",

    # Brand
    "ruby",
    "micelio",
    "github",
    "gitlab",
    "bitbucket",

    # Locale prefixes (used for SEO-friendly locale routing)
    "en",
    "es",
    "ko",
    "ja",
    "zh_cn",
    "zh_tw"
  ]

  @doc """
  Returns the list of reserved handles.
  """
  def reserved do
    @reserved
  end
end
