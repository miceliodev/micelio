defmodule MicelioWeb.PromptRequestLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.PromptRequests
  alias Micelio.Repo
  alias Micelio.Repositories
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  defp unique_email(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}@example.com"
  end

  defp setup_repository do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("prompt-live"))
    org_handle = unique_handle("prompt-live-org")
    repository_handle = unique_handle("prompt-live-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Prompt Live Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repository_handle,
        name: "Prompt Live Project",
        organization_id: organization.id
      })

    {user, organization, repository}
  end

  test "lists prompt requests and creates a new one", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests"
      )

    assert has_element?(view, "#new-prompt-request")

    {:ok, form_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests/new"
      )

    conversation_json = ~s({"messages":[{"role":"user","content":"Ship it"}]})
    generated_at = DateTime.utc_now() |> DateTime.to_iso8601()

    form =
      form(form_view, "#prompt-request-form",
        prompt_request: %{
          title: "Ship prompt request",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: "ai_generated",
          token_count: "1200",
          generated_at: generated_at,
          system_prompt: "System",
          prompt: "Do the thing",
          result: "Diff output",
          conversation: conversation_json
        }
      )

    render_submit(form)

    [prompt_request] = PromptRequests.list_prompt_requests_for_repository(repository)

    assert_redirect(
      form_view,
      ~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests/#{prompt_request.id}"
    )
  end

  test "shows prompt request diff and accepts suggestions", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Review diff",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 820,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert has_element?(view, "#prompt-request-diff")

    suggestion_form =
      form(view, "#prompt-suggestion-form",
        prompt_suggestion: %{suggestion: "Make the prompt more specific"}
      )

    render_submit(suggestion_form)

    assert render(view) =~ "Make the prompt more specific"
  end

  test "shows validation runs for a prompt request", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Review validation",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 820,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, run} = ValidationEnvironments.create_run(prompt_request, %{status: :passed})

    run
    |> ValidationRun.changeset(%{
      metrics: %{"duration_ms" => 1200},
      resource_usage: %{"cpu_seconds" => 3.2, "memory_mb" => 256},
      coverage_delta: 0.01,
      check_results: %{"checks" => [%{"id" => "test"}]}
    })
    |> Repo.update!()

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert has_element?(view, "#prompt-request-run-validation")
    assert render(view) =~ "Validation Runs"
    assert render(view) =~ "Passed"
    assert render(view) =~ "Coverage delta"
  end
end
