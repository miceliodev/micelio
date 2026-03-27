defmodule Micelio.PlansTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.AITokens.TokenEarning
  alias Micelio.Plans
  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.Sessions

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  defp setup_repository do
    handle = unique_handle("prompt")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "org-#{handle}",
        name: "Prompt Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "project-#{handle}",
        name: "Prompt Project",
        organization_id: organization.id
      })

    {user, repository}
  end

  test "creates plan with agent context" do
    {user, repository} = setup_repository()

    attrs = %{
      title: "Add plan system",
      prompt: "Implement the plan flow",
      result: "Diff output",
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 1420,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System instructions",
      conversation: %{
        "messages" => [
          %{"role" => "user", "content" => "Implement a feature"}
        ]
      }
    }

    assert {:ok, plan} =
             Plans.create_plan(attrs, repository: repository, user: user)

    assert plan.repository_id == repository.id
    assert plan.user_id == user.id
    assert plan.conversation["messages"] != []
    assert Plans.attestation_status(plan) == :verified

    assert [listed] = Plans.list_plans_for_repository(repository)
    assert listed.id == plan.id
  end

  test "captures execution metadata and lineage" do
    {user, repository} = setup_repository()

    {:ok, parent} =
      Plans.create_plan(
        %{
          title: "Parent prompt",
          prompt: "Initial prompt",
          result: "Initial result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    execution_environment = %{"runtime" => "phoenix", "os" => "linux"}

    {:ok, child} =
      Plans.create_plan(
        %{
          title: "Child prompt",
          prompt: "Follow-up prompt",
          result: "Follow-up result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 900,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
          parent_plan_id: parent.id,
          execution_environment: execution_environment,
          execution_duration_ms: 12_500
        },
        project: repository,
        user: user
      )

    assert child.parent_plan_id == parent.id
    assert child.execution_environment["runtime"] == "phoenix"
    assert child.execution_duration_ms == 12_500
  end

  test "rejects plan when generation depth exceeds limit" do
    {user, repository} = setup_repository()

    {:ok, root} =
      Plans.create_plan(
        %{
          title: "Root prompt",
          prompt: "Root prompt",
          result: "Root result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    {:ok, child} =
      Plans.create_plan(
        %{
          title: "Child prompt",
          prompt: "Child prompt",
          result: "Child result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 600,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
          parent_plan_id: root.id
        },
        project: repository,
        user: user
      )

    assert {:error, changeset} =
             Plans.create_plan(
               %{
                 title: "Third prompt",
                 prompt: "Third prompt",
                 result: "Third result",
                 model: "gpt-4.1",
                 model_version: "2025-02-01",
                 origin: :ai_generated,
                 token_count: 700,
                 generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
                 system_prompt: "System",
                 conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
                 parent_plan_id: child.id
               },
               project: repository,
               user: user,
               max_generation_depth: 2
             )

    assert "exceeds max generation depth" in errors_on(changeset).parent_plan_id
  end

  test "submit_plan validates and accepts plans" do
    {user, repository} = setup_repository()

    attrs = %{
      title: "Validate submission",
      prompt: "Do the thing",
      result: "Output",
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 2100,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System",
      conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]},
      execution_environment: %{"runtime" => "mix", "os" => "linux"},
      execution_duration_ms: 4500
    }

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 5000, reserved: 0})

    {:ok, plan} =
      Plans.submit_plan(attrs,
        project: repository,
        user: user,
        validation_enabled: true,
        validation_async: false,
        task_budget_amount: "3000",
        validation_opts: [
          provider_module: Micelio.TestValidationProvider,
          provider_opts: [notify_pid: self()],
          executor: Micelio.TestValidationExecutor,
          plan_attrs: %{
            provider: "aws",
            image: "micelio/validation-runner:latest",
            cpu_cores: 2,
            memory_mb: 1024,
            disk_gb: 10,
            ttl_seconds: 1200,
            network: "egress"
          }
        ]
      )

    updated = Repo.get!(Plan, plan.id)
    assert updated.review_status == :accepted
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.session_id == "plan-#{plan.id}"
    assert session.metadata["plan"]["prompt"] == attrs.prompt

    assert session.metadata["plan"]["execution_environment"] ==
             attrs.execution_environment

    assert session.metadata["plan"]["execution_duration_ms"] ==
             attrs.execution_duration_ms

    assert is_binary(session.metadata["plan"]["attestation"]["signature"])
    [run | _] = Plans.list_validation_runs(updated)
    assert run.status == :passed
  end

  test "keeps plan pending when confidence is low after validation" do
    {user, repository} = setup_repository()

    attrs = %{
      title: "Low confidence submission",
      prompt: "Do the thing",
      result: "Output",
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 150_000,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System",
      conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
    }

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 200_000, reserved: 0})

    {:ok, plan} =
      Plans.submit_plan(attrs,
        project: repository,
        user: user,
        validation_enabled: true,
        validation_async: false,
        task_budget_amount: "200000",
        validation_opts: [
          provider_module: Micelio.TestValidationProvider,
          provider_opts: [notify_pid: self()],
          executor: Micelio.TestValidationExecutor,
          plan_attrs: %{
            provider: "aws",
            image: "micelio/validation-runner:latest",
            cpu_cores: 2,
            memory_mb: 1024,
            disk_gb: 10,
            ttl_seconds: 1200,
            network: "egress"
          }
        ]
      )

    updated = Repo.get!(Plan, plan.id)
    assert updated.review_status == :pending
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert updated.session_id == nil

    [run | _] = Plans.list_validation_runs(updated)
    assert run.status == :passed
  end

  test "submit_plan stores feedback when validation fails" do
    {user, repository} = setup_repository()

    attrs = %{
      title: "Failing submission",
      prompt: "Do the thing",
      result: "Output",
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 2100,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System",
      conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
    }

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 5000, reserved: 0})

    assert {:error, {:validation_failed, feedback, failed_plan}} =
             Plans.submit_plan(attrs,
               project: repository,
               user: user,
               validation_enabled: true,
               validation_async: false,
               task_budget_amount: "3000",
               validation_opts: [
                 provider_module: Micelio.TestValidationProvider,
                 provider_opts: [notify_pid: self()],
                 executor: Micelio.TestFailingValidationExecutor,
                 plan_attrs: %{
                   provider: "aws",
                   image: "micelio/validation-runner:latest",
                   cpu_cores: 2,
                   memory_mb: 1024,
                   disk_gb: 10,
                   ttl_seconds: 1200,
                   network: "egress"
                 }
               ]
             )

    assert is_map(feedback)
    assert feedback["summary"] =~ "Validation failed"
    assert Enum.any?(feedback["failures"], &(&1["check_id"] == "test"))

    assert failed_plan.repository_id == repository.id

    [plan | _] = Plans.list_plans_for_repository(repository)
    updated = Repo.get!(Plan, plan.id)
    assert updated.review_status == :rejected
    assert updated.validation_iterations == 1
    assert is_binary(updated.validation_feedback)
    assert updated.session_id == nil
    [run | _] = Plans.list_validation_runs(updated)
    assert run.status == :failed
  end

  test "reviewing plans as accepted creates a session" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Create session",
          prompt: "Do the work",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 900,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    assert {:ok, updated} = Plans.review_plan(plan, user, :accepted)
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.goal == "Create session"
    assert session.metadata["plan"]["result"] == "Output"
  end

  test "creates plan improvement suggestions" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Improve prompt",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 620,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    assert {:ok, _suggestion} =
             Plans.create_plan_suggestion(
               plan,
               %{suggestion: "Add constraints for edge cases"},
               user: user
             )

    assert [suggestion] = Plans.list_plan_suggestions(plan)
    assert suggestion.suggestion =~ "edge cases"
  end

  test "awards token earnings for thorough plan suggestions" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Suggestion rewards",
          prompt: "Improve prompt quality",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 620,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    suggestion_text =
      String.duplicate(
        "Add explicit acceptance criteria and mention edge cases to reduce ambiguity. ",
        3
      )

    assert Repo.aggregate(TokenEarning, :count, :id) == 0

    assert {:ok, suggestion} =
             Plans.create_plan_suggestion(
               plan,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    earning =
      Repo.get_by!(TokenEarning,
        plan_suggestion_id: suggestion.id,
        reason: :plan_suggestion_submitted
      )

    assert earning.amount == AITokens.plan_suggestion_reward(suggestion)
    assert earning.user_id == user.id
    assert earning.repository_id == repository.id
  end

  test "does not award suggestion earnings for short feedback" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Short suggestion",
          prompt: "Improve prompt quality",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 620,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    assert {:ok, _suggestion} =
             Plans.create_plan_suggestion(
               plan,
               %{suggestion: "Consider edge cases."},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 0
  end

  test "awards only one suggestion earning per user and plan" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Multiple suggestions",
          prompt: "Improve prompt quality",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 620,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    suggestion_text =
      String.duplicate(
        "Provide concrete examples and specify success criteria for the task. ",
        3
      )

    assert {:ok, _suggestion} =
             Plans.create_plan_suggestion(
               plan,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    assert {:ok, _suggestion} =
             Plans.create_plan_suggestion(
               plan,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1
  end

  test "accepts human-origin plans with model metadata" do
    {user, repository} = setup_repository()

    assert {:ok, plan} =
             Plans.create_plan(
               %{
                 title: "Human authored fix",
                 prompt: "Summarize the change",
                 result: "Manual diff summary",
                 model: "gpt-4.1",
                 model_version: "2025-02-01",
                 origin: :human,
                 token_count: 0,
                 generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
                 system_prompt: "System",
                 conversation: %{
                   "messages" => [
                     %{"role" => "user", "content" => "Manual change"}
                   ]
                 }
               },
               project: repository,
               user: user
             )

    assert plan.model == "gpt-4.1"
    assert plan.model_version == "2025-02-01"
    assert plan.token_count == 0
    assert plan.generated_at != nil
    assert Plans.attestation_status(plan) == :verified
    assert plan.attestation["payload"]["origin"] == "human"
  end

  test "runs validation for a plan and records runs" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Validate contribution",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 2100,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 5000, reserved: 0})

    assert {:ok, _budget, _pool} =
             AITokens.upsert_task_budget(plan, %{"amount" => "3000"})

    assert {:ok, run} =
             Plans.run_validation(plan,
               provider_module: Micelio.TestValidationProvider,
               provider_opts: [notify_pid: self()],
               executor: Micelio.TestValidationExecutor,
               plan_attrs: %{
                 provider: "aws",
                 image: "micelio/validation-runner:latest",
                 cpu_cores: 2,
                 memory_mb: 1024,
                 disk_gb: 10,
                 ttl_seconds: 1200,
                 network: "egress"
               }
             )

    assert run.status == :passed
    assert run.coverage_delta == 0.03
    assert run.metrics["duration_ms"] >= 0
    assert run.resource_usage["cpu_seconds"] == 3.5
    assert run.resource_usage["memory_mb"] == 128
    assert_received {:validate_request, _request}
    assert_received {:provision, _request}
    assert_received {:terminate, %{id: "test-vm"}}

    [listed | _] = Plans.list_validation_runs(plan)
    assert listed.id == run.id
  end

  test "run_validation_async promotes plan to a session when validation passes" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Async validation promotion",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 2100,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(repository, %{balance: 5000, reserved: 0})

    assert {:ok, _budget, _pool} =
             AITokens.upsert_task_budget(plan, %{"amount" => "3000"})

    assert {:ok, pid} =
             Plans.run_validation_async(plan, self(),
               provider_module: Micelio.TestValidationProvider,
               executor: Micelio.TestValidationExecutor,
               plan_attrs: %{
                 provider: "aws",
                 image: "micelio/validation-runner:latest",
                 cpu_cores: 2,
                 memory_mb: 1024,
                 disk_gb: 10,
                 ttl_seconds: 1200,
                 network: "egress"
               }
             )

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    plan_id = plan.id
    assert_receive {:validation_finished, ^plan_id, {:ok, _run}}, 5_000

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000

    updated = Repo.get!(Plan, plan.id)

    assert updated.review_status == :accepted
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.session_id == "plan-#{plan.id}"
  end

  test "run_validation requires a task budget for ai plans" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Validate contribution without budget",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: repository,
        user: user
      )

    assert {:error, :missing_budget} =
             Plans.run_validation(plan,
               provider_module: Micelio.TestValidationProvider,
               executor: Micelio.TestValidationExecutor,
               plan_attrs: %{
                 provider: "aws",
                 image: "micelio/validation-runner:latest",
                 cpu_cores: 2,
                 memory_mb: 1024,
                 disk_gb: 10,
                 ttl_seconds: 1200,
                 network: "egress"
               }
             )

    assert [] == Plans.list_validation_runs(plan)
  end

  test "marks attestation invalid when plan data is tampered" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Audit attestation",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    plan
    |> Ecto.Changeset.change(%{token_count: plan.token_count + 1})
    |> Repo.update!()

    updated = Repo.get!(Plan, plan.id)
    assert Plans.attestation_status(updated) == :invalid
  end

  test "updates review status for plans" do
    {user, repository} = setup_repository()

    {:ok, reviewer} = Accounts.get_or_create_user_by_email("reviewer@example.com")

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Review status check",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    assert plan.review_status == :pending

    {:ok, updated} = Plans.review_plan(plan, reviewer, :accepted)

    assert updated.review_status == :accepted
    assert updated.reviewed_by_id == reviewer.id
    assert updated.reviewed_at != nil
  end

  test "awards token earnings when plans are accepted" do
    {user, repository} = setup_repository()

    {:ok, reviewer} = Accounts.get_or_create_user_by_email("earnings-reviewer@example.com")

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Earn tokens",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    assert Repo.aggregate(TokenEarning, :count, :id) == 0

    {:ok, accepted} = Plans.review_plan(plan, reviewer, :accepted)

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    earning =
      Repo.get_by!(TokenEarning,
        plan_id: accepted.id,
        reason: :plan_accepted
      )

    assert earning.amount == AITokens.plan_reward(accepted)
    assert earning.user_id == user.id
    assert earning.repository_id == repository.id

    {:ok, _} = Plans.review_plan(accepted, reviewer, :accepted)
    assert Repo.aggregate(TokenEarning, :count, :id) == 1
  end

  test "lists plan registry with search and review status filters" do
    {user, repository} = setup_repository()

    {:ok, reviewer} = Accounts.get_or_create_user_by_email("registry-reviewer@example.com")

    base_attrs = %{
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 1200,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System",
      conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
    }

    {:ok, accepted_request} =
      Plans.create_plan(
        Map.merge(base_attrs, %{
          title: "Bug fix prompt",
          prompt: "Fix a bug in the registry",
          result: "Patch applied"
        }),
        project: repository,
        user: user
      )

    {:ok, rejected_request} =
      Plans.create_plan(
        Map.merge(base_attrs, %{
          title: "Refactor prompt",
          prompt: "Refactor a subsystem",
          result: "Refactor diff"
        }),
        project: repository,
        user: user
      )

    {:ok, accepted_request} =
      Plans.review_plan(accepted_request, reviewer, :accepted)

    {:ok, _rejected_request} =
      Plans.review_plan(rejected_request, reviewer, :rejected)

    [listed] =
      Plans.list_plan_registry(
        search: "Bug fix",
        review_status: :accepted
      )

    assert listed.id == accepted_request.id
    assert [] == Plans.list_plan_registry(review_status: :pending)
    assert [_] = Plans.list_plan_registry(review_status: :rejected)
  end

  test "curates plans and filters curated registry" do
    {user, repository} = setup_repository()

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Curate me",
          prompt: "Do a thing",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 900,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: repository,
        user: user
      )

    assert [] == Plans.list_plan_registry(curated_only: true)

    {:ok, curated} = Plans.curate_plan(plan, user)
    assert curated.curated_at
    assert curated.curated_by_id == user.id

    [listed] = Plans.list_plan_registry(curated_only: true)
    assert listed.id == curated.id
  end

  test "creates and approves plan templates for registry use" do
    {user, repository} = setup_repository()

    {:ok, template} =
      Plans.create_plan_template(
        %{
          name: "Bug fix template",
          description: "Template for fixing a bug",
          prompt: "Fix the bug described in the issue.",
          system_prompt: "You are a careful code reviewer.",
          category: "bug fix"
        },
        created_by: user
      )

    assert [] == Plans.list_plan_templates(only_approved: true)

    {:ok, approved} = Plans.approve_plan_template(template, user)
    [listed] = Plans.list_plan_templates(only_approved: true)
    assert listed.id == approved.id

    {:ok, plan} =
      Plans.create_plan(
        %{
          title: "Template prompt",
          prompt: "Use the template",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 750,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
          plan_template_id: approved.id
        },
        project: repository,
        user: user
      )

    assert plan.plan_template_id == approved.id
  end
end
