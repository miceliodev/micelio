defmodule Micelio.Sessions.OGSummaryTest do
  use Micelio.DataCase, async: false

  import Mimic

  alias Micelio.Sessions.Session
  alias Micelio.{Accounts, Projects, Repo, Sessions}

  setup :verify_on_exit!
  setup :set_mimic_global

  test "generates and caches LLM summaries for agent OG images" do
    unique = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} = Accounts.get_or_create_user_by_email("agent-summary-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-summary-org-#{unique}",
        name: "Agent Summary Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-summary-project-#{unique}",
        name: "Agent Summary Project",
        description: "Public project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-summary-session-#{unique}",
        goal: "Summarize agent changes",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/summary.ex",
        change_type: "added",
        content: "defmodule Summary do\nend\n"
      })

    expect(Req, :post, fn endpoint, opts ->
      assert endpoint == "https://example.com/v1/responses"
      assert opts[:json][:model] == "gpt-4.1-mini"
      assert String.contains?(opts[:json][:input], "lib/summary.ex")

      {:ok, %{body: %{"summary" => "Added summary module for agent changes."}}}
    end)

    session = Sessions.get_session_with_changes(session.id)

    og_summary_opts = [
      llm_endpoint: "https://example.com/v1/responses",
      llm_api_key: "secret-key",
      llm_model: "gpt-4.1-mini"
    ]

    assert {:ok, "Added summary module for agent changes."} =
             Sessions.get_or_generate_og_summary(session, session.changes, og_summary_opts)

    reloaded = Repo.get!(Session, session.id) |> Repo.preload(:changes)

    assert reloaded.metadata["og_summary"] == "Added summary module for agent changes."
    assert is_binary(reloaded.metadata["og_summary_hash"])

    assert {:ok, "Added summary module for agent changes."} =
             Sessions.get_or_generate_og_summary(reloaded, reloaded.changes, og_summary_opts)
  end

  test "normalizes LLM summaries to ASCII and 160 characters max" do
    unique = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} = Accounts.get_or_create_user_by_email("agent-summary-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-summary-org-#{unique}",
        name: "Agent Summary Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-summary-project-#{unique}",
        name: "Agent Summary Project",
        description: "Public project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-summary-session-#{unique}",
        goal: "Summarize agent changes",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/summary.ex",
        change_type: "added",
        content: "defmodule Summary do\nend\n"
      })

    non_ascii = <<240, 159, 152, 132>>

    long_summary =
      "Added report dashboards #{non_ascii} with alerts and expanded metrics for admin monitoring. " <>
        String.duplicate("More details ", 20)

    expect(Req, :post, fn _endpoint, _opts ->
      {:ok, %{body: %{"summary" => long_summary}}}
    end)

    session = Sessions.get_session_with_changes(session.id)

    og_summary_opts = [
      llm_endpoint: "https://example.com/v1/responses",
      llm_api_key: "secret-key",
      llm_model: "gpt-4.1-mini"
    ]

    assert {:ok, summary} =
             Sessions.get_or_generate_og_summary(session, session.changes, og_summary_opts)

    assert String.length(summary) == 160
    assert summary =~ "Added report dashboards"
    refute String.contains?(summary, non_ascii)
    assert String.match?(summary, ~r/^[\x20-\x7E]+$/)
  end
end
