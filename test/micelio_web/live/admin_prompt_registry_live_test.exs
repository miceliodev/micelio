defmodule MicelioWeb.AdminPromptRegistryLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.PromptRequests
  alias Micelio.Repositories

  test "shows prompt registry for admins", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(admin, %{name: "Prompt Org", handle: "prompt-org"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        name: "Prompt Project",
        handle: "prompt-project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Registry entry",
          prompt: "Prompt",
          result: "Result",
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
          origin: :ai_generated,
          model: "gpt-4",
          model_version: "2025-02-01",
          token_count: 120,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        project: repository,
        user: admin
      )

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/prompts")

    assert render(view) =~ "Prompt registry"
    assert render(view) =~ "Registry entry"
    assert render(view) =~ "admin-prompt-#{prompt_request.id}"
  end
end
