# Seeds for local development
alias Micelio.Accounts
alias Micelio.Accounts.OrganizationMembership
alias Micelio.Mic.Project, as: MicProject
alias Micelio.Mic.Seed
alias Micelio.Repo
alias Micelio.Repositories
alias Micelio.Repositories.Repository
alias Micelio.Sessions

user_email = "test@micelio.dev"
org_handle = "micelio"
org_name = "Micelio"
repo_handle = "micelio"
repo_name = "Micelio"
repo_description = "Forge platform for AI-native development"
repo_url = "https://micelio.dev/docs"
repo_visibility = "public"
workspace_root = Path.join([File.cwd!(), "seeds", "cli"])
grpc_url = System.get_env("MICELIO_GRPC_URL") || "http://localhost:50051"

organization_result =
  case Accounts.get_organization_by_handle(org_handle) do
    {:ok, org} ->
      {:ok, org}

    {:error, :not_found} ->
      Accounts.create_organization(%{handle: org_handle, name: org_name}, allow_reserved: true)
  end

with {:ok, user} <- Accounts.get_or_create_user_by_email(user_email),
     {:ok, organization} <- organization_result do
  case Accounts.get_organization_membership(user.id, organization.id) do
    nil ->
      {:ok, _membership} =
        Accounts.create_organization_membership(%{
          user_id: user.id,
          organization_id: organization.id,
          role: :admin
        })

    %OrganizationMembership{role: :admin} ->
      :ok

    %OrganizationMembership{} = membership ->
      {:ok, _membership} =
        membership
        |> OrganizationMembership.changeset(%{role: :admin})
        |> Repo.update()
  end

  repo_attrs = %{
    handle: repo_handle,
    name: repo_name,
    description: repo_description,
    url: repo_url,
    visibility: repo_visibility,
    organization_id: organization.id
  }

  repository =
    case Repositories.get_repository_by_handle(organization.id, repo_handle) do
      nil ->
        case Repositories.create_repository(repo_attrs) do
          {:ok, repo} -> repo
          {:error, reason} -> raise "Failed to create repository: #{inspect(reason)}"
        end

      %Repository{} = repo ->
        update_attrs =
          Enum.reduce([:name, :description, :url], %{}, fn key, acc ->
            value = Map.get(repo, key)
            desired = Map.get(repo_attrs, key)

            if value in [nil, ""], do: Map.put(acc, key, desired), else: acc
          end)

        update_attrs =
          if repo.visibility == repo_visibility do
            update_attrs
          else
            Map.put(update_attrs, :visibility, repo_visibility)
          end

        if update_attrs == %{} do
          repo
        else
          case Repositories.update_repository_settings(repo, update_attrs) do
            {:ok, repo} -> repo
            {:error, reason} -> raise "Failed to update repository: #{inspect(reason)}"
          end
        end
    end

  IO.puts("Ensured repository: #{org_handle}/#{repository.handle}")

  # Seed workspace files
  File.mkdir_p!(workspace_root)

  readme_path = Path.join(workspace_root, "README.md")
  package_path = Path.join(workspace_root, "package.json")
  index_path = Path.join(workspace_root, "index.js")
  micignore_path = Path.join(workspace_root, ".micignore")

  if not File.exists?(readme_path) do
    File.write!(readme_path, """
    # micelio-cli

    Minimal Node CLI for Micelio local development.

    ## Usage

    ```bash
    node index.js
    ```
    """)
  end

  if not File.exists?(package_path) do
    File.write!(package_path, """
    {
      "name": "micelio-cli",
      "version": "0.1.0",
      "description": "Node CLI example for Micelio",
      "type": "module",
      "bin": {
        "micelio-cli": "./index.js"
      },
      "scripts": {
        "start": "node index.js"
      }
    }
    """)
  end

  if not File.exists?(index_path) do
    File.write!(index_path, """
    #!/usr/bin/env node
    console.log("micelio-cli ready");
    """)
  end

  if not File.exists?(micignore_path) do
    File.write!(micignore_path, """
    node_modules/
    .mic/
    """)
  end

  seed_result =
    case Seed.seed_repository_from_path(repository.id, workspace_root) do
      {:ok, %{tree_hash: tree_hash} = result} ->
        {:seeded, tree_hash, result}

      {:error, :already_seeded} ->
        {:already_seeded, nil, %{}}

      {:error, reason} ->
        raise "Failed to seed workspace: #{inspect(reason)}"
    end

  {position, tree_hash} =
    case MicProject.get_head(repository.id) do
      {:ok, %{position: position, tree_hash: head_hash}} ->
        {position, head_hash}

      {:ok, nil} ->
        {1, elem(seed_result, 1)}

      {:error, reason} ->
        raise "Failed to read head: #{inspect(reason)}"
    end

  if not is_binary(tree_hash) do
    raise "Failed to resolve workspace tree hash"
  end

  {:ok, tree} = MicProject.get_tree(repository.id, tree_hash)

  manifest = %{
    "version" => 1,
    "server" => grpc_url,
    "account" => org_handle,
    "project" => repository.handle,
    "position" => position,
    "tree_hash" => Base.encode16(tree_hash, case: :lower),
    "entries" =>
      tree
      |> Enum.sort_by(fn {path, _hash} -> path end)
      |> Enum.map(fn {path, hash} ->
        %{"path" => path, "hash" => Base.encode16(hash, case: :lower)}
      end)
  }

  File.mkdir_p!(Path.join(workspace_root, ".mic"))
  File.write!(Path.join([workspace_root, ".mic", "workspace.json"]), Jason.encode!(manifest))

  IO.puts("Linked local workspace: #{workspace_root} -> #{org_handle}/#{repository.handle}")

  # ============ Seed sessions with rich data ============

  IO.puts("\nSeeding sessions...")

  # Session 1: Landed, AI contributor - dark mode feature
  {:ok, session1} =
    Sessions.create_session(%{
      session_id: "seed-session-dark-mode-#{System.unique_integer([:positive])}",
      goal: "Add dark mode support to the design system",
      repository_id: repository.id,
      user_id: user.id,
      conversation: [
        %{
          "role" => "user",
          "content" =>
            "We need dark mode support for the design system. The tokens should switch based on prefers-color-scheme and a manual toggle.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "I will add dark mode by creating CSS custom properties that respond to both prefers-color-scheme media query and a data-theme attribute on :root. This gives us automatic system preference detection plus manual override.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-3540) |> DateTime.to_iso8601()
        },
        %{
          "role" => "user",
          "content" =>
            "Make sure all the semantic colors have dark variants. The contrast ratios need to meet WCAG AA.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-3000) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "Done. I have added dark mode variants for all semantic colors (text, background, surface, border, muted, primary, danger, success). All combinations pass WCAG AA contrast requirements. The toggle uses data-theme attribute on the root element.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-2700) |> DateTime.to_iso8601()
        }
      ],
      decisions: [
        %{
          "decision" => "Use CSS custom properties with media query and data-theme",
          "reasoning" =>
            "Custom properties allow runtime switching without JavaScript class toggling on every element. The media query provides automatic detection, while data-theme allows manual override."
        },
        %{
          "decision" => "WCAG AA contrast ratios for all color pairs",
          "reasoning" =>
            "Accessibility compliance is non-negotiable. All foreground/background combinations were tested with contrast ratio tools."
        }
      ],
      metadata: %{
        "contributor_type" => "ai",
        "model_id" => "claude-sonnet-4-20250514",
        "tool_name" => "Claude Code",
        "tool_version" => "1.2.0"
      }
    })

  {:ok, session1} = Sessions.land_session(session1)

  Sessions.create_session_change(%{
    session_id: session1.id,
    file_path: "assets/css/theme/tokens.css",
    change_type: "modified",
    content:
      ":root { --color-text: #1f2328; } @media (prefers-color-scheme: dark) { :root { --color-text: #f0f6fc; } }",
    metadata: %{"size" => 2480}
  })

  Sessions.create_session_change(%{
    session_id: session1.id,
    file_path: "assets/css/theme/tokens-dark.css",
    change_type: "added",
    content: ":root[data-theme='dark'] { --color-bg: #0d1117; --color-surface: #151b23; }",
    metadata: %{"size" => 1240}
  })

  Sessions.create_session_change(%{
    session_id: session1.id,
    file_path: "assets/css/app.css",
    change_type: "modified",
    content: "@import 'theme/tokens-dark.css';",
    metadata: %{"size" => 580}
  })

  Sessions.capture_session_event(session1.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "running", "message" => "Analyzing existing token structure"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601()
  })

  Sessions.capture_session_event(session1.session_id, %{
    "type" => "progress",
    "payload" => %{"percent" => 50, "message" => "Dark mode tokens generated"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-3000) |> DateTime.to_iso8601()
  })

  Sessions.capture_session_event(session1.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "completed", "message" => "All dark mode tokens applied"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-2400) |> DateTime.to_iso8601()
  })

  IO.puts("  Created session: #{session1.goal} (landed, AI)")

  # Session 2: Landed, human contributor - auth fix
  {:ok, session2} =
    Sessions.create_session(%{
      session_id: "seed-session-auth-fix-#{System.unique_integer([:positive])}",
      goal: "Fix authentication redirect loop on expired tokens",
      repository_id: repository.id,
      user_id: user.id,
      conversation: [
        %{
          "role" => "user",
          "content" =>
            "Users are getting stuck in a redirect loop when their session token expires. The browser keeps bouncing between /auth/login and the protected page.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "I can see the issue. The authentication plug checks for a valid token and redirects to login, but the login page also checks for an existing token and redirects back. When the token is expired but present, both redirects fire.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-7080) |> DateTime.to_iso8601()
        },
        %{
          "role" => "user",
          "content" =>
            "Right. The fix should clear the expired token before redirecting to login.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-6600) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "I have updated the authentication plug to check token expiry explicitly. If the token exists but is expired, it gets cleared from the session before the redirect to login. This breaks the loop.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-6000) |> DateTime.to_iso8601()
        },
        %{
          "role" => "user",
          "content" => "Also add a flash message so users know why they were logged out.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-5700) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "Added. The flash message says 'Your session has expired. Please sign in again.' Users will see it on the login page after the redirect.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-5500) |> DateTime.to_iso8601()
        }
      ],
      decisions: [
        %{
          "decision" => "Clear expired tokens in the auth plug before redirect",
          "reasoning" =>
            "The root cause was an expired-but-present token triggering both the 'has token, redirect to app' and 'invalid token, redirect to login' paths. Clearing it before redirect ensures a clean state."
        }
      ],
      metadata: %{
        "contributor_type" => "human"
      }
    })

  {:ok, session2} = Sessions.land_session(session2)

  Sessions.create_session_change(%{
    session_id: session2.id,
    file_path: "lib/micelio_web/plugs/authentication_plug.ex",
    change_type: "modified",
    content:
      ~s{defp handle_expired_token(conn) do\n  conn |> clear_session() |> put_flash(:info, "Your session has expired.") |> redirect(to: ~p"/auth/login")\nend},
    metadata: %{"size" => 890}
  })

  Sessions.create_session_change(%{
    session_id: session2.id,
    file_path: "test/micelio_web/plugs/authentication_plug_test.exs",
    change_type: "modified",
    content: "test \"redirects with flash on expired token\" do\n  # ...\nend",
    metadata: %{"size" => 1560}
  })

  Sessions.capture_session_event(session2.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "running", "message" => "Investigating redirect loop"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.to_iso8601()
  })

  Sessions.capture_session_event(session2.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "completed", "message" => "Fix applied and tests passing"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-5400) |> DateTime.to_iso8601()
  })

  IO.puts("  Created session: #{session2.goal} (landed, human)")

  # Session 3: Active, mixed contributor - search feature
  {:ok, session3} =
    Sessions.create_session(%{
      session_id: "seed-session-search-#{System.unique_integer([:positive])}",
      goal: "Implement repository search with full-text indexing",
      repository_id: repository.id,
      user_id: user.id,
      conversation: [
        %{
          "role" => "user",
          "content" =>
            "We need full-text search across repositories. Users should be able to search by name, description, and file contents.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-900) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "I will implement this using PostgreSQL's built-in tsvector full-text search. This avoids external dependencies while giving us ranked results with highlights.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-840) |> DateTime.to_iso8601()
        },
        %{
          "role" => "user",
          "content" =>
            "Good approach. Start with name and description, we can add file content search later.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-600) |> DateTime.to_iso8601()
        }
      ],
      decisions: [
        %{
          "decision" => "Use PostgreSQL tsvector for full-text search",
          "reasoning" =>
            "PostgreSQL FTS is built-in, supports ranking and highlights, and avoids the operational overhead of Elasticsearch or similar. We can always migrate later if needed."
        }
      ],
      metadata: %{
        "contributor_type" => "mixed",
        "model_id" => "claude-sonnet-4-20250514",
        "tool_name" => "Claude Code",
        "tool_version" => "1.3.0"
      }
    })

  Sessions.create_session_change(%{
    session_id: session3.id,
    file_path: "lib/micelio/search.ex",
    change_type: "added",
    content:
      "defmodule Micelio.Search do\n  @moduledoc \"Full-text search across repositories.\"\n  # ...\nend",
    metadata: %{"size" => 3200}
  })

  Sessions.capture_session_event(session3.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "running", "message" => "Generating search module"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-600) |> DateTime.to_iso8601()
  })

  Sessions.capture_session_event(session3.session_id, %{
    "type" => "output",
    "payload" => %{
      "text" =>
        "$ mix ecto.gen.migration add_search_index\n* creating priv/repo/migrations/20260209_add_search_index.exs\n\n$ mix ecto.migrate\n[info] == Running migration\n[info] create index repositories_search_idx\n[info] == Migrated in 0.1s",
      "stream" => "stdout"
    },
    "timestamp" => DateTime.utc_now() |> DateTime.add(-300) |> DateTime.to_iso8601()
  })

  IO.puts("  Created session: #{session3.goal} (active, mixed)")

  # Session 4: Abandoned, AI contributor - failed migration attempt
  {:ok, session4} =
    Sessions.create_session(%{
      session_id: "seed-session-cockroach-#{System.unique_integer([:positive])}",
      goal: "Migrate database to CockroachDB",
      repository_id: repository.id,
      user_id: user.id,
      conversation: [
        %{
          "role" => "user",
          "content" =>
            "Can we migrate from PostgreSQL to CockroachDB for better horizontal scaling?",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-1800) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "I will evaluate CockroachDB compatibility. Let me check our query patterns and Ecto usage for any PostgreSQL-specific features.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-1740) |> DateTime.to_iso8601()
        },
        %{
          "role" => "assistant",
          "content" =>
            "After analysis, I found several blockers: we use PostgreSQL-specific features like tsvector for search, advisory locks for Oban job processing, and JSONB operators that CockroachDB does not fully support.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-1500) |> DateTime.to_iso8601()
        },
        %{
          "role" => "user",
          "content" =>
            "That sounds like too many incompatibilities. Let's abandon this for now and revisit if we hit actual scaling limits.",
          "timestamp" => DateTime.utc_now() |> DateTime.add(-1320) |> DateTime.to_iso8601()
        }
      ],
      metadata: %{
        "contributor_type" => "ai",
        "model_id" => "claude-sonnet-4-20250514",
        "tool_name" => "Claude Code",
        "tool_version" => "1.2.0"
      }
    })

  {:ok, _session4} = Sessions.abandon_session(session4)

  Sessions.capture_session_event(session4.session_id, %{
    "type" => "status",
    "payload" => %{"state" => "running", "message" => "Analyzing PostgreSQL compatibility"},
    "timestamp" => DateTime.utc_now() |> DateTime.add(-1800) |> DateTime.to_iso8601()
  })

  Sessions.capture_session_event(session4.session_id, %{
    "type" => "error",
    "payload" => %{
      "message" =>
        "Incompatible query patterns detected: tsvector, advisory locks, JSONB containment operators"
    },
    "timestamp" => DateTime.utc_now() |> DateTime.add(-1200) |> DateTime.to_iso8601()
  })

  IO.puts("  Created session: #{session4.goal} (abandoned, AI)")

  IO.puts("\nLocal development setup complete!")
  IO.puts("Login with: #{user.email}")
else
  {:error, reason} ->
    raise "Failed to ensure Micelio seed data: #{inspect(reason)}"
end
