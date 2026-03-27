defmodule Micelio.AITokensTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.AITokens.TokenContribution
  alias Micelio.Plans
  alias Micelio.Repo

  setup do
    {:ok, organization} =
      Accounts.create_organization(%{handle: "ai-tokens", name: "AI Tokens"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "token-pool",
        name: "Token Pool",
        organization_id: organization.id
      })

    {:ok, organization: organization, repository: repository}
  end

  test "create_token_pool/2 persists defaults", %{repository: repository} do
    assert {:ok, pool} = AITokens.create_token_pool(repository)
    assert pool.repository_id == repository.id
    assert pool.balance == 0
    assert pool.reserved == 0
  end

  test "get_or_create_token_pool/1 reuses existing pool", %{repository: repository} do
    assert {:ok, pool} = AITokens.get_or_create_token_pool(repository)
    assert {:ok, same_pool} = AITokens.get_or_create_token_pool(repository)
    assert pool.id == same_pool.id
  end

  test "update_token_pool/2 rejects reserved above balance", %{repository: repository} do
    assert {:ok, pool} = AITokens.create_token_pool(repository)

    assert {:error, changeset} =
             AITokens.update_token_pool(pool, %{balance: 5, reserved: 10})

    assert "cannot exceed balance" in errors_on(changeset).reserved
  end

  test "repository_usage_summary/1 aggregates usage metrics", %{repository: repository} do
    {:ok, user} = Accounts.get_or_create_user_by_email("usage@example.com")

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Usage prompt",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 120,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, _} = Plans.review_plan(plan, user, :accepted)

    {:ok, rejected_plan} =
      Plans.create_plan(
        %{
          title: "Usage reject",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 30,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, _} = Plans.review_plan(rejected_plan, user, :rejected)

    {:ok, _} =
      Plans.create_plan(
        %{
          title: "Human prompt",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :human,
          token_count: 0,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    summary = AITokens.repository_usage_summary(repository)

    assert summary.tokens_spent == 150
    assert summary.accepted_plans == 1
    assert summary.total_plans == 3
  end

  test "contribute_tokens/3 records contribution and updates balance", %{repository: repository} do
    {:ok, user} = Accounts.get_or_create_user_by_email("donor@example.com")

    assert {:ok, contribution, pool} =
             AITokens.contribute_tokens(repository, user, %{"amount" => "25"})

    assert contribution.amount == 25
    assert contribution.repository_id == repository.id
    assert contribution.user_id == user.id
    assert pool.balance == 25
    assert Repo.aggregate(TokenContribution, :count, :id) == 1
  end

  test "contribute_tokens/3 rejects non-positive amounts", %{repository: repository} do
    {:ok, user} = Accounts.get_or_create_user_by_email("donor-two@example.com")

    assert {:error, changeset} =
             AITokens.contribute_tokens(repository, user, %{"amount" => "0"})

    assert "must be greater than 0" in errors_on(changeset).amount
  end

  test "upsert_task_budget/2 reserves tokens for a plan", %{repository: repository} do
    {:ok, user} = Accounts.get_or_create_user_by_email("budgeter@example.com")

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Budget task",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 200,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, pool} = AITokens.create_token_pool(repository, %{balance: 120, reserved: 0})

    assert {:ok, budget, updated_pool} =
             AITokens.upsert_task_budget(plan, %{"amount" => "40"})

    assert budget.amount == 40
    assert updated_pool.id == pool.id
    assert updated_pool.reserved == 40

    assert {:ok, budget, updated_pool} =
             AITokens.upsert_task_budget(plan, %{"amount" => "70"})

    assert budget.amount == 70
    assert updated_pool.reserved == 70
  end

  test "upsert_task_budget/2 rejects allocations above available", %{repository: repository} do
    {:ok, user} = Accounts.get_or_create_user_by_email("budgeter-two@example.com")

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Budget overflow",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 200,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 50, reserved: 0})

    assert {:error, :insufficient_tokens} =
             AITokens.upsert_task_budget(plan, %{"amount" => "70"})
  end
end
