defmodule MicelioWeb.PromptRequestLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.PromptRequests

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
    repository_handle = unique_handle("prompt-live-repo")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Prompt Live Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: repository_handle,
        name: "Prompt Live Repo",
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
        ~p"/#{organization.account.handle}/#{repository.handle}/prs"
      )

    assert has_element?(view, "#new-prompt-request")
    assert has_element?(view, "#prompt-requests-empty")

    {:ok, form_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs/new"
      )

    form =
      form(form_view, "#prompt-request-form",
        prompt_request: %{
          title: "Ship prompt request",
          description: "Describe the change to make"
        }
      )

    render_submit(form)

    [prompt_request] = PromptRequests.list_prompt_requests_for_repository(repository)
    assert prompt_request.number == 1
    assert prompt_request.title == "Ship prompt request"

    assert_redirect(
      form_view,
      ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{prompt_request.number}"
    )
  end

  test "shows a prompt request", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_simple_prompt_request(
        %{"title" => "Review this", "description" => "Some description"},
        repository: repository,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs/#{prompt_request.number}"
      )

    assert html =~ "Review this"
    assert html =~ "##{prompt_request.number}"
    assert has_element?(view, "#prompt-request-description")
  end

  test "assigns sequential numbers to prompt requests", %{conn: _conn} do
    {user, _organization, repository} = setup_repository()

    {:ok, pr1} =
      PromptRequests.create_simple_prompt_request(
        %{"title" => "First"},
        repository: repository,
        user: user
      )

    {:ok, pr2} =
      PromptRequests.create_simple_prompt_request(
        %{"title" => "Second"},
        repository: repository,
        user: user
      )

    assert pr1.number == 1
    assert pr2.number == 2
  end

  test "index shows prompt request list when not empty", %{conn: conn} do
    {user, organization, repository} = setup_repository()

    {:ok, _pr} =
      PromptRequests.create_simple_prompt_request(
        %{"title" => "A prompt request"},
        repository: repository,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, html} =
      live(
        conn,
        ~p"/#{organization.account.handle}/#{repository.handle}/prs"
      )

    assert html =~ "A prompt request"
    assert has_element?(view, "#prompt-requests-list")
    refute has_element?(view, "#prompt-requests-empty")
  end
end
