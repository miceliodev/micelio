defmodule MicelioWeb.AgentLiveTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use MicelioWeb.ConnCase, async: false

  import Mimic
  import Phoenix.LiveViewTest

  alias Micelio.Sessions.OGSummary
  alias Micelio.{Accounts, Projects, Sessions}
  alias MicelioWeb.OpenGraphImage

  setup :verify_on_exit!
  setup :set_mimic_global

  test "renders active agent sessions for public projects", %{conn: conn} do
    %{user: user, organization: organization, repository: repository} = create_public_repository()

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-progress-session",
        goal: "Stream live agent updates",
        repository_id: repository.id,
        user_id: user.id,
        conversation: [
          %{"role" => "user", "content" => "Kick off work"},
          %{"role" => "assistant", "content" => "Working on it"}
        ],
        decisions: [%{"decision" => "Track progress", "reasoning" => "Visibility"}]
      })

    {:ok, _change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/progress.ex",
        change_type: "added",
        content: "defmodule Progress do\nend\n"
      })

    {:ok, view, _html} =
      live(conn, "/#{organization.account.handle}/#{repository.handle}/agents")

    assert has_element?(view, "#agent-progress")
    assert has_element?(view, "#agent-progress-list")
    assert has_element?(view, "#agent-session-#{session.id}")

    assert has_element?(
             view,
             "#agent-session-#{session.id} .agent-progress-goal",
             session.goal
           )
  end

  test "shows empty state when no active sessions exist", %{conn: conn} do
    %{organization: organization, repository: repository} = create_public_repository()

    {:ok, view, _html} =
      live(conn, "/#{organization.account.handle}/#{repository.handle}/agents")

    assert has_element?(view, "#agent-progress-empty")
  end

  test "agent progress og:image uses cached LLM summary", %{conn: conn} do
    %{user: user, organization: organization, repository: repository} = create_public_repository()

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-og-session",
        goal: "Ship OG summary",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/og_summary.ex",
        change_type: "added",
        content: "defmodule OGSummary do\nend\n"
      })

    summary = "Added OG summary module for agent progress updates."
    digest = OGSummary.digest([change])

    {:ok, _session} =
      Sessions.update_session(session, %{
        metadata: %{
          "og_summary" => summary,
          "og_summary_hash" => digest
        }
      })

    html =
      conn
      |> get("/#{organization.account.handle}/#{repository.handle}/agents")
      |> html_response(200)

    doc = LazyHTML.from_document(html)
    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    %{"token" => token} = URI.decode_query(uri.query || "")

    assert {:ok, attrs} = OpenGraphImage.verify_token(token)
    assert attrs["description"] == summary
    assert attrs["image_template"] == "agent_progress"
    assert attrs["image_stats"]["commits"] == 1
    assert attrs["image_stats"]["files"] == 1
  end

  test "agent progress og:image generates LLM summary when missing", %{conn: conn} do
    %{user: user, organization: organization, repository: repository} = create_public_repository()

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-og-missing-session",
        goal: "Ship OG summaries",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/og_summary.ex",
        change_type: "added",
        content: "defmodule OGSummary do\nend\n"
      })

    summary = "Added OG summary module for agent progress updates."

    expect(Req, :post, fn endpoint, opts ->
      assert endpoint == "https://example.com/v1/responses"
      assert opts[:json][:model] == "gpt-4.1-mini"
      assert String.contains?(opts[:json][:input], "lib/og_summary.ex")

      {:ok, %{body: %{"summary" => summary}}}
    end)

    conn =
      init_test_session(conn, %{
        og_summary_opts: [
          llm_endpoint: "https://example.com/v1/responses",
          llm_api_key: "secret-key",
          llm_model: "gpt-4.1-mini"
        ]
      })

    html =
      conn
      |> get("/#{organization.account.handle}/#{repository.handle}/agents")
      |> html_response(200)

    doc = LazyHTML.from_document(html)
    tag = LazyHTML.query(doc, ~S|meta[property="og:image"]|)
    [image_url] = LazyHTML.attribute(tag, "content")

    uri = URI.parse(image_url)
    %{"token" => token} = URI.decode_query(uri.query || "")

    assert {:ok, attrs} = OpenGraphImage.verify_token(token)
    assert attrs["description"] == summary
  end

  test "redirects when project is private for anonymous viewer", %{conn: conn} do
    %{organization: organization, repository: repository} = create_private_repository()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Project not found."}}}} =
             live(conn, "/#{organization.account.handle}/#{repository.handle}/agents")
  end

  defp create_public_repository do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} =
      Accounts.get_or_create_user_by_email("agent-progress-#{unique_suffix}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-org-#{unique_suffix}",
        name: "Agent Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-project-#{unique_suffix}",
        name: "Agent Project",
        description: "Public project",
        organization_id: organization.id,
        visibility: "public"
      })

    %{user: user, organization: organization, repository: repository}
  end

  defp create_private_repository do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} =
      Accounts.get_or_create_user_by_email("agent-private-#{unique_suffix}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-private-org-#{unique_suffix}",
        name: "Agent Private Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-private-project-#{unique_suffix}",
        name: "Agent Private Project",
        description: "Private project",
        organization_id: organization.id,
        visibility: "private"
      })

    %{user: user, organization: organization, repository: repository}
  end
end
