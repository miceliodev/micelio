defmodule Micelio.ContributionConfidenceTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.ContributionConfidence
  alias Micelio.PromptRequests
  alias Micelio.Repo
  alias Micelio.Repositories
  alias Micelio.ValidationEnvironments.ValidationRun

  defp setup_prompt_request(attrs) do
    {:ok, user} = Accounts.get_or_create_user_by_email("confidence@example.com")

    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "confidence-org-#{unique}",
        name: "Confidence Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "confidence-project-#{unique}",
        name: "Confidence Project",
        organization_id: organization.id
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(attrs, repository: repository, user: user)

    prompt_request
  end

  test "scores prompt requests using validation, reputation, and token efficiency" do
    prompt_request =
      setup_prompt_request(%{
        title: "Add confidence scoring",
        prompt: "Implement contribution confidence scoring",
        result: "Diff output",
        model: "gpt-4.1",
        model_version: "2025-02-01",
        origin: :ai_generated,
        token_count: 2000,
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        system_prompt: "System",
        conversation: %{"messages" => [%{"role" => "user", "content" => "Ship it"}]}
      })

    {:ok, run} =
      %ValidationRun{}
      |> ValidationRun.changeset(%{
        status: :passed,
        prompt_request_id: prompt_request.id,
        metrics: %{"quality_score" => 90}
      })
      |> Repo.insert()

    score =
      ContributionConfidence.score_for_prompt_request(prompt_request,
        validation_run: run,
        reputation: 80,
        token_baseline: 2000
      )

    assert score.components.validation == 90
    assert score.components.reputation == 80
    assert score.components.token_efficiency == 50
    assert score.overall == 79
    assert score.label == "Medium"
  end

  test "uses the latest validation run when scoring lists" do
    prompt_request =
      setup_prompt_request(%{
        title: "Score list request",
        prompt: "Use latest validation run",
        result: "Diff output",
        model: "gpt-4.1",
        model_version: "2025-02-01",
        origin: :ai_generated,
        token_count: 600,
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        system_prompt: "System",
        conversation: %{"messages" => [%{"role" => "user", "content" => "Ship it"}]}
      })

    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    {:ok, _run} =
      %ValidationRun{}
      |> ValidationRun.changeset(%{
        status: :failed,
        prompt_request_id: prompt_request.id,
        metrics: %{"quality_score" => 20},
        completed_at: past
      })
      |> Repo.insert()

    {:ok, _run} =
      %ValidationRun{}
      |> ValidationRun.changeset(%{
        status: :passed,
        prompt_request_id: prompt_request.id,
        metrics: %{"quality_score" => 85},
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    scores =
      ContributionConfidence.scores_for_prompt_requests([prompt_request],
        reputation_by_user_id: %{prompt_request.user_id => %Micelio.Reputation.Score{overall: 65}}
      )

    assert scores[prompt_request.id].components.validation == 85
  end

  test "defaults scores when data is missing" do
    prompt_request =
      setup_prompt_request(%{
        title: "Human prompt",
        prompt: "Manual update",
        result: "Diff output",
        model: "human",
        origin: :human,
        system_prompt: "System",
        conversation: %{"messages" => [%{"role" => "user", "content" => "Ship it"}]}
      })

    score =
      ContributionConfidence.score_for_prompt_request(prompt_request,
        validation_runs: [],
        reputation: 50
      )

    assert score.components.validation == 50
    assert score.components.token_efficiency == 50
  end

  test "auto_accept? uses default threshold and overrides" do
    assert ContributionConfidence.auto_accept?(%ContributionConfidence.Score{overall: 60})
    refute ContributionConfidence.auto_accept?(%ContributionConfidence.Score{overall: 59})

    assert ContributionConfidence.auto_accept?(%ContributionConfidence.Score{overall: 75},
             auto_accept_threshold: 70
           )

    refute ContributionConfidence.auto_accept?(%ContributionConfidence.Score{overall: 70},
             auto_accept_threshold: 75
           )
  end
end
