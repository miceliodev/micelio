defmodule Micelio.PromptRequestsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.AITokens.TokenEarning
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repo
  alias Micelio.Repositories
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

  test "creates prompt request with agent context" do
    {user, repository} = setup_repository()

    attrs = %{
      title: "Add prompt request system",
      prompt: "Implement the prompt request flow",
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

    assert {:ok, prompt_request} =
             PromptRequests.create_prompt_request(attrs, repository: repository, user: user)

    assert prompt_request.repository_id == repository.id
    assert prompt_request.user_id == user.id
    assert prompt_request.conversation["messages"] != []
    assert PromptRequests.attestation_status(prompt_request) == :verified

    assert [listed] = PromptRequests.list_prompt_requests_for_repository(repository)
    assert listed.id == prompt_request.id
  end

  test "captures execution metadata and lineage" do
    {user, repository} = setup_repository()

    {:ok, parent} =
      PromptRequests.create_prompt_request(
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
      PromptRequests.create_prompt_request(
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
          parent_prompt_request_id: parent.id,
          execution_environment: execution_environment,
          execution_duration_ms: 12_500
        },
        project: repository,
        user: user
      )

    assert child.parent_prompt_request_id == parent.id
    assert child.execution_environment["runtime"] == "phoenix"
    assert child.execution_duration_ms == 12_500
  end

  test "rejects prompt request when generation depth exceeds limit" do
    {user, repository} = setup_repository()

    {:ok, root} =
      PromptRequests.create_prompt_request(
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
      PromptRequests.create_prompt_request(
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
          parent_prompt_request_id: root.id
        },
        project: repository,
        user: user
      )

    assert {:error, changeset} =
             PromptRequests.create_prompt_request(
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
                 parent_prompt_request_id: child.id
               },
               project: repository,
               user: user,
               max_generation_depth: 2
             )

    assert "exceeds max generation depth" in errors_on(changeset).parent_prompt_request_id
  end

  test "submit_prompt_request validates and accepts prompt requests" do
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

    {:ok, prompt_request} =
      PromptRequests.submit_prompt_request(attrs,
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

    updated = Repo.get!(PromptRequest, prompt_request.id)
    assert updated.review_status == :accepted
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.session_id == "prompt-request-#{prompt_request.id}"
    assert session.metadata["prompt_request"]["prompt"] == attrs.prompt

    assert session.metadata["prompt_request"]["execution_environment"] ==
             attrs.execution_environment

    assert session.metadata["prompt_request"]["execution_duration_ms"] ==
             attrs.execution_duration_ms

    assert is_binary(session.metadata["prompt_request"]["attestation"]["signature"])
    [run | _] = PromptRequests.list_validation_runs(updated)
    assert run.status == :passed
  end

  test "keeps prompt request pending when confidence is low after validation" do
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

    {:ok, prompt_request} =
      PromptRequests.submit_prompt_request(attrs,
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

    updated = Repo.get!(PromptRequest, prompt_request.id)
    assert updated.review_status == :pending
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert updated.session_id == nil

    [run | _] = PromptRequests.list_validation_runs(updated)
    assert run.status == :passed
  end

  test "submit_prompt_request stores feedback when validation fails" do
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

    assert {:error, {:validation_failed, feedback, failed_prompt_request}} =
             PromptRequests.submit_prompt_request(attrs,
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

    assert failed_prompt_request.repository_id == repository.id

    [prompt_request | _] = PromptRequests.list_prompt_requests_for_repository(repository)
    updated = Repo.get!(PromptRequest, prompt_request.id)
    assert updated.review_status == :rejected
    assert updated.validation_iterations == 1
    assert is_binary(updated.validation_feedback)
    assert updated.session_id == nil
    [run | _] = PromptRequests.list_validation_runs(updated)
    assert run.status == :failed
  end

  test "reviewing prompt requests as accepted creates a session" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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

    assert {:ok, updated} = PromptRequests.review_prompt_request(prompt_request, user, :accepted)
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.goal == "Create session"
    assert session.metadata["prompt_request"]["result"] == "Output"
  end

  test "creates prompt improvement suggestions" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: "Add constraints for edge cases"},
               user: user
             )

    assert [suggestion] = PromptRequests.list_prompt_suggestions(prompt_request)
    assert suggestion.suggestion =~ "edge cases"
  end

  test "awards token earnings for thorough prompt suggestions" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    earning =
      Repo.get_by!(TokenEarning,
        prompt_suggestion_id: suggestion.id,
        reason: :prompt_suggestion_submitted
      )

    assert earning.amount == AITokens.prompt_suggestion_reward(suggestion)
    assert earning.user_id == user.id
    assert earning.repository_id == repository.id
  end

  test "does not award suggestion earnings for short feedback" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: "Consider edge cases."},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 0
  end

  test "awards only one suggestion earning per user and prompt request" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    assert {:ok, _suggestion} =
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: suggestion_text},
               user: user
             )

    assert Repo.aggregate(TokenEarning, :count, :id) == 1
  end

  test "accepts human-origin prompt requests with model metadata" do
    {user, repository} = setup_repository()

    assert {:ok, prompt_request} =
             PromptRequests.create_prompt_request(
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

    assert prompt_request.model == "gpt-4.1"
    assert prompt_request.model_version == "2025-02-01"
    assert prompt_request.token_count == 0
    assert prompt_request.generated_at != nil
    assert PromptRequests.attestation_status(prompt_request) == :verified
    assert prompt_request.attestation["payload"]["origin"] == "human"
  end

  test "runs validation for a prompt request and records runs" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "3000"})

    assert {:ok, run} =
             PromptRequests.run_validation(prompt_request,
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

    [listed | _] = PromptRequests.list_validation_runs(prompt_request)
    assert listed.id == run.id
  end

  test "run_validation_async promotes prompt request to a session when validation passes" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "3000"})

    assert {:ok, pid} =
             PromptRequests.run_validation_async(prompt_request, self(),
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

    prompt_request_id = prompt_request.id
    assert_receive {:validation_finished, ^prompt_request_id, {:ok, _run}}, 5_000

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000

    updated = Repo.get!(PromptRequest, prompt_request.id)

    assert updated.review_status == :accepted
    assert updated.validation_feedback == nil
    assert updated.validation_iterations == 1
    assert is_binary(updated.session_id)

    session = Sessions.get_session(updated.session_id)
    assert session.session_id == "prompt-request-#{prompt_request.id}"
  end

  test "run_validation requires a task budget for ai prompt requests" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
             PromptRequests.run_validation(prompt_request,
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

    assert [] == PromptRequests.list_validation_runs(prompt_request)
  end

  test "marks attestation invalid when prompt request data is tampered" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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

    prompt_request
    |> Ecto.Changeset.change(%{token_count: prompt_request.token_count + 1})
    |> Repo.update!()

    updated = Repo.get!(PromptRequest, prompt_request.id)
    assert PromptRequests.attestation_status(updated) == :invalid
  end

  test "updates review status for prompt requests" do
    {user, repository} = setup_repository()

    {:ok, reviewer} = Accounts.get_or_create_user_by_email("reviewer@example.com")

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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

    assert prompt_request.review_status == :pending

    {:ok, updated} = PromptRequests.review_prompt_request(prompt_request, reviewer, :accepted)

    assert updated.review_status == :accepted
    assert updated.reviewed_by_id == reviewer.id
    assert updated.reviewed_at != nil
  end

  test "awards token earnings when prompt requests are accepted" do
    {user, repository} = setup_repository()

    {:ok, reviewer} = Accounts.get_or_create_user_by_email("earnings-reviewer@example.com")

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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

    {:ok, accepted} = PromptRequests.review_prompt_request(prompt_request, reviewer, :accepted)

    assert Repo.aggregate(TokenEarning, :count, :id) == 1

    earning =
      Repo.get_by!(TokenEarning,
        prompt_request_id: accepted.id,
        reason: :prompt_request_accepted
      )

    assert earning.amount == AITokens.prompt_request_reward(accepted)
    assert earning.user_id == user.id
    assert earning.repository_id == repository.id

    {:ok, _} = PromptRequests.review_prompt_request(accepted, reviewer, :accepted)
    assert Repo.aggregate(TokenEarning, :count, :id) == 1
  end

  test "lists prompt registry with search and review status filters" do
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
      PromptRequests.create_prompt_request(
        Map.merge(base_attrs, %{
          title: "Bug fix prompt",
          prompt: "Fix a bug in the registry",
          result: "Patch applied"
        }),
        project: repository,
        user: user
      )

    {:ok, rejected_request} =
      PromptRequests.create_prompt_request(
        Map.merge(base_attrs, %{
          title: "Refactor prompt",
          prompt: "Refactor a subsystem",
          result: "Refactor diff"
        }),
        project: repository,
        user: user
      )

    {:ok, accepted_request} =
      PromptRequests.review_prompt_request(accepted_request, reviewer, :accepted)

    {:ok, _rejected_request} =
      PromptRequests.review_prompt_request(rejected_request, reviewer, :rejected)

    [listed] =
      PromptRequests.list_prompt_registry(
        search: "Bug fix",
        review_status: :accepted
      )

    assert listed.id == accepted_request.id
    assert [] == PromptRequests.list_prompt_registry(review_status: :pending)
    assert [_] = PromptRequests.list_prompt_registry(review_status: :rejected)
  end

  test "curates prompt requests and filters curated registry" do
    {user, repository} = setup_repository()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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

    assert [] == PromptRequests.list_prompt_registry(curated_only: true)

    {:ok, curated} = PromptRequests.curate_prompt_request(prompt_request, user)
    assert curated.curated_at
    assert curated.curated_by_id == user.id

    [listed] = PromptRequests.list_prompt_registry(curated_only: true)
    assert listed.id == curated.id
  end

  test "creates and approves prompt templates for registry use" do
    {user, repository} = setup_repository()

    {:ok, template} =
      PromptRequests.create_prompt_template(
        %{
          name: "Bug fix template",
          description: "Template for fixing a bug",
          prompt: "Fix the bug described in the issue.",
          system_prompt: "You are a careful code reviewer.",
          category: "bug fix"
        },
        created_by: user
      )

    assert [] == PromptRequests.list_prompt_templates(only_approved: true)

    {:ok, approved} = PromptRequests.approve_prompt_template(template, user)
    [listed] = PromptRequests.list_prompt_templates(only_approved: true)
    assert listed.id == approved.id

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
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
          prompt_template_id: approved.id
        },
        project: repository,
        user: user
      )

    assert prompt_request.prompt_template_id == approved.id
  end
end
