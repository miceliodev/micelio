defmodule Micelio.AgentInfraTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AgentInfra
  alias Micelio.AITokens
  alias Micelio.PromptRequests
  alias Micelio.Repositories

  defp setup_prompt_request do
    {:ok, user} = Accounts.get_or_create_user_by_email("agent-runner@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-runner-org",
        name: "Agent Runner Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "agent-runner-project",
        name: "Agent Runner Project",
        organization_id: organization.id
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Agent runner budget check",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1000,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    {user, repository, prompt_request}
  end

  defp plan_attrs do
    %{
      provider: "aws",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 12,
      ttl_seconds: 900,
      network: "egress"
    }
  end

  test "build_request_with_quota requires a task budget for agent runs" do
    {user, _project, prompt_request} = setup_prompt_request()

    assert {:error, :missing_budget} =
             AgentInfra.build_request_with_quota(user.account, plan_attrs(),
               prompt_request: prompt_request
             )
  end

  test "build_request_with_quota succeeds when budget covers the prompt request" do
    {user, repository, prompt_request} = setup_prompt_request()

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 2000, reserved: 0})

    assert {:ok, _budget, _pool} =
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "1500"})

    assert {:ok, request} =
             AgentInfra.build_request_with_quota(user.account, plan_attrs(),
               prompt_request: prompt_request,
               limits: %{billable_units: 2_000_000}
             )

    assert request.provider == "aws"
    assert request.image == "micelio/agent-runner:latest"
  end
end
