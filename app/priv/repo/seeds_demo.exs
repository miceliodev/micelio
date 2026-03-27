# Demo seed data for Micelio
# Run with: mix run priv/repo/seeds_demo.exs

alias Micelio.{Repo, Accounts, Projects, Sessions}
alias Micelio.Accounts.{User, Organization, OrganizationMembership}

# Clean up existing demo data (optional - comment out if you want to keep existing data)
Repo.delete_all(Sessions.Session)
Repo.delete_all(Projects.Project)
Repo.delete_all(OrganizationMembership)
Repo.delete_all(Organization)
Repo.delete_all(User)

IO.puts("Creating demo user...")

# Create demo user
{:ok, user} = Accounts.get_or_create_user_by_email("demo@micelio.dev")

IO.puts("✓ Demo user created: #{user.email}")

IO.puts("Creating demo organization...")

# Create demo organization
{:ok, organization} = Accounts.create_organization_for_user(user, %{
  handle: "demo-org",
  name: "Demo Organization"
})

IO.puts("✓ Demo organization created: #{organization.account.handle}")

IO.puts("Creating demo projects...")

# Create demo projects
{:ok, web_app_project} = Projects.create_project(%{
  handle: "web-app",
  name: "Web Application",
  description: "A modern web application built with Phoenix LiveView",
  organization_id: organization.id
})

IO.puts("✓ Project created: #{web_app_project.handle}")

{:ok, api_service_project} = Projects.create_project(%{
  handle: "api-service",
  name: "API Service",
  description: "A REST API service for data management",
  organization_id: organization.id
})

IO.puts("✓ Project created: #{api_service_project.handle}")

IO.puts("Creating demo sessions for web-app...")

# Web App Sessions

# Session 1: Active session (in progress)
{:ok, active_session} = Sessions.create_session(%{
  session_id: "demo-session-001",
  goal: "Add user authentication with OAuth",
  project_id: web_app_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "I need to add user authentication to the web app"},
    %{"role" => "assistant", "content" => "I'll help you implement OAuth authentication. Let me start by checking the current setup."},
    %{"role" => "user", "content" => "We want to support Google and GitHub providers"}
  ],
  decisions: [
    %{"decision" => "Use Ueberauth library for OAuth", "reasoning" => "It's the most mature OAuth solution for Elixir with wide provider support"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "web-app",
    files_count: 5
  }
})

IO.puts("✓ Active session created")

# Session 2: Landed session with full conversation
{:ok, landed_session} = Sessions.create_session(%{
  session_id: "demo-session-002",
  goal: "Implement real-time chat functionality",
  project_id: web_app_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-86400, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "We need to add a real-time chat feature for users"},
    %{"role" => "assistant", "content" => "Great! Phoenix Channels are perfect for this. Let me create the necessary modules."},
    %{"role" => "user", "content" => "Can we store message history in the database?"},
    %{"role" => "assistant", "content" => "Yes, I'll create a Messages schema and handle persistence."},
    %{"role" => "user", "content" => "Perfect! Also need online presence indicators"},
    %{"role" => "assistant", "content" => "Added Phoenix Presence for tracking online users. All done!"}
  ],
  decisions: [
    %{"decision" => "Use Phoenix Channels for real-time communication", "reasoning" => "Built-in, performant, and well-integrated with LiveView"},
    %{"decision" => "Store messages in PostgreSQL", "reasoning" => "Reliable persistence with full-text search capabilities"},
    %{"decision" => "Implement Phoenix Presence for user status", "reasoning" => "Standard solution for presence tracking in Phoenix apps"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "web-app",
    files_count: 12
  }
})

{:ok, _} = Sessions.land_session(landed_session)

IO.puts("✓ Landed session created")

# Session 3: Abandoned session
{:ok, abandoned_session} = Sessions.create_session(%{
  session_id: "demo-session-003",
  goal: "Migrate to Tailwind CSS",
  project_id: web_app_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-172800, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "I want to migrate our CSS to Tailwind"},
    %{"role" => "assistant", "content" => "I can help with that. Let me start by installing the dependencies."},
    %{"role" => "user", "content" => "Actually, let's hold off on this for now"}
  ],
  decisions: [],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "web-app",
    files_count: 2
  }
})

{:ok, _} = Sessions.abandon_session(abandoned_session)

IO.puts("✓ Abandoned session created")

# Session 4: Landed session with multiple decisions
{:ok, multi_decision_session} = Sessions.create_session(%{
  session_id: "demo-session-004",
  goal: "Set up CI/CD pipeline",
  project_id: web_app_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-259200, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "Need to set up automated testing and deployment"},
    %{"role" => "assistant", "content" => "I'll create a GitHub Actions workflow for you."},
    %{"role" => "user", "content" => "We need separate environments for staging and production"},
    %{"role" => "assistant", "content" => "Added environment-specific workflows with approval gates."},
    %{"role" => "user", "content" => "Also need database migration handling"},
    %{"role" => "assistant", "content" => "Integrated migration steps in the deployment workflow."}
  ],
  decisions: [
    %{"decision" => "Use GitHub Actions for CI/CD", "reasoning" => "Already using GitHub, native integration, free for open source"},
    %{"decision" => "Implement blue-green deployment", "reasoning" => "Zero-downtime deployments with easy rollback"},
    %{"decision" => "Run migrations before deployment", "reasoning" => "Ensures database schema is up-to-date before new code runs"},
    %{"decision" => "Require manual approval for production", "reasoning" => "Additional safety gate for production deployments"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "web-app",
    files_count: 8
  }
})

{:ok, _} = Sessions.land_session(multi_decision_session)

IO.puts("✓ Multi-decision session created")

# Session 5: Another active session
{:ok, active_session_2} = Sessions.create_session(%{
  session_id: "demo-session-005",
  goal: "Add email notification system",
  project_id: web_app_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "Users should receive email notifications for important events"},
    %{"role" => "assistant", "content" => "I'll set up Swoosh for email delivery. Which events need notifications?"},
    %{"role" => "user", "content" => "New messages, mentions, and weekly summaries"}
  ],
  decisions: [
    %{"decision" => "Use Swoosh with SendGrid adapter", "reasoning" => "Reliable email delivery with good Phoenix integration"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "web-app",
    files_count: 6
  }
})

IO.puts("✓ Second active session created")

IO.puts("Creating demo sessions for api-service...")

# API Service Sessions

# Session 1: Landed session
{:ok, api_session_1} = Sessions.create_session(%{
  session_id: "demo-session-006",
  goal: "Implement API rate limiting",
  project_id: api_service_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-432000, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "We need to add rate limiting to prevent API abuse"},
    %{"role" => "assistant", "content" => "I'll implement a token bucket algorithm with Redis for distributed rate limiting."},
    %{"role" => "user", "content" => "Different limits for free vs paid tiers?"},
    %{"role" => "assistant", "content" => "Yes, I've added tiered rate limits based on user subscription."}
  ],
  decisions: [
    %{"decision" => "Use Redis for rate limit tracking", "reasoning" => "Fast, distributed, with built-in TTL support"},
    %{"decision" => "Implement token bucket algorithm", "reasoning" => "Allows burst traffic while maintaining long-term limits"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "api-service",
    files_count: 4
  }
})

{:ok, _} = Sessions.land_session(api_session_1)

IO.puts("✓ API service landed session created")

# Session 2: Active session
{:ok, api_session_2} = Sessions.create_session(%{
  session_id: "demo-session-007",
  goal: "Add GraphQL endpoint",
  project_id: api_service_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-1800, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "Some clients want a GraphQL endpoint instead of REST"},
    %{"role" => "assistant", "content" => "I'll add Absinthe for GraphQL support. Let me create the schema."}
  ],
  decisions: [],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "api-service",
    files_count: 3
  }
})

IO.puts("✓ API service active session created")

# Session 3: Landed session with comprehensive workflow
{:ok, api_session_3} = Sessions.create_session(%{
  session_id: "demo-session-008",
  goal: "Implement comprehensive API documentation",
  project_id: api_service_project.id,
  user_id: user.id,
  started_at: DateTime.utc_now() |> DateTime.add(-604800, :second) |> DateTime.truncate(:second),
  conversation: [
    %{"role" => "user", "content" => "We need better API documentation with interactive examples"},
    %{"role" => "assistant", "content" => "I'll set up OpenAPI/Swagger documentation with Phoenix Swagger."},
    %{"role" => "user", "content" => "Can users try the API directly from the docs?"},
    %{"role" => "assistant", "content" => "Yes, I've configured Swagger UI for interactive API testing."},
    %{"role" => "user", "content" => "We also need code examples in multiple languages"},
    %{"role" => "assistant", "content" => "Added code generation for Python, JavaScript, Ruby, and Go."}
  ],
  decisions: [
    %{"decision" => "Use OpenAPI 3.0 specification", "reasoning" => "Industry standard with wide tool support"},
    %{"decision" => "Integrate Swagger UI", "reasoning" => "Provides interactive API exploration and testing"},
    %{"decision" => "Generate client libraries", "reasoning" => "Makes integration easier for developers"}
  ],
  metadata: %{
    organization_handle: "demo-org",
    project_handle: "api-service",
    files_count: 15
  }
})

{:ok, _} = Sessions.land_session(api_session_3)

IO.puts("✓ API service comprehensive session created")

IO.puts("\n🎉 Demo data created successfully!")
IO.puts("\nDemo credentials:")
IO.puts("  Email: demo@micelio.dev")
IO.puts("  Password: password123")
IO.puts("\nDemo organization: demo-org")
IO.puts("Demo projects:")
IO.puts("  - web-app (#{Micelio.Sessions.count_sessions_for_project(web_app_project)} sessions)")
IO.puts("  - api-service (#{Micelio.Sessions.count_sessions_for_project(api_service_project)} sessions)")
