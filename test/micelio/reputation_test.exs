defmodule Micelio.ReputationTest do
  use Micelio.DataCase, async: true

  import Ecto.Query, warn: false

  alias Micelio.Accounts
  alias Micelio.Plans
  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.Repositories
  alias Micelio.Reputation
  alias Micelio.Sessions
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun

  defp setup_repository(email) do
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "rep-org-#{System.unique_integer([:positive])}",
        name: "Rep Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "rep-project-#{System.unique_integer([:positive])}",
        name: "Rep Project",
        organization_id: organization.id
      })

    {user, repository}
  end

  defp create_plan(user, repository, attrs \\ %{}) do
    Plans.create_plan(
      Map.merge(
        %{
          title: "Fix validation",
          prompt: "Fix failing tests",
          result: "Diff",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Fix"}]}
        },
        attrs
      ),
      project: repository,
      user: user
    )
  end

  test "builds trust scores with per-type tracks" do
    {user, repository} = setup_repository("rep-user@example.com")

    {:ok, plan} = create_plan(user, repository, %{title: "Docs update"})
    {:ok, _reviewed} = Plans.review_plan(plan, user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(plan, %{status: :passed})

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "rep-session",
        goal: "Fix login bug",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(session)

    score = Reputation.trust_score_for_user(user)

    assert score.overall >= 0
    assert Map.has_key?(score.by_type, :docs)
    assert Map.has_key?(score.by_type, :tests)
    assert Map.has_key?(score.by_type, :features)
    assert Map.has_key?(score.by_type, :fixes)
  end

  test "penalizes rejected contributions that passed validation" do
    {good_user, repository} = setup_repository("rep-good@example.com")

    {:ok, good_plan} = create_plan(good_user, repository)
    {:ok, _reviewed} = Plans.review_plan(good_plan, good_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(good_plan, %{status: :passed})

    good_score = Reputation.trust_score_for_user(good_user).overall

    {bad_user, bad_project} = setup_repository("rep-bad@example.com")

    {:ok, bad_plan} = create_plan(bad_user, bad_project)
    {:ok, _reviewed} = Plans.review_plan(bad_plan, bad_user, :rejected)
    {:ok, _run} = ValidationEnvironments.create_run(bad_plan, %{status: :passed})

    bad_score = Reputation.trust_score_for_user(bad_user).overall

    assert bad_score <= good_score
  end

  test "reduces trust score when review iterations increase" do
    {clean_user, repository} = setup_repository("rep-clean@example.com")

    {:ok, clean_plan} = create_plan(clean_user, repository)
    {:ok, _reviewed} = Plans.review_plan(clean_plan, clean_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(clean_plan, %{status: :passed})

    clean_score = Reputation.trust_score_for_user(clean_user).overall

    {iter_user, iter_project} = setup_repository("rep-iter@example.com")

    {:ok, iter_plan} = create_plan(iter_user, iter_project)

    for index <- 1..5 do
      {:ok, _suggestion} =
        Plans.create_plan_suggestion(
          iter_plan,
          %{suggestion: "Iteration #{index}"},
          user: iter_user
        )
    end

    {:ok, _reviewed} = Plans.review_plan(iter_plan, iter_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(iter_plan, %{status: :passed})

    iter_score = Reputation.trust_score_for_user(iter_user).overall

    assert iter_score < clean_score
  end

  test "decays trust score for older contributions" do
    {recent_user, recent_project} = setup_repository("rep-recent@example.com")

    {:ok, recent_plan} = create_plan(recent_user, recent_project)
    {:ok, _reviewed} = Plans.review_plan(recent_plan, recent_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(recent_plan, %{status: :passed})

    recent_score = Reputation.trust_score_for_user(recent_user).overall

    {old_user, old_project} = setup_repository("rep-old@example.com")

    {:ok, old_plan} = create_plan(old_user, old_project)
    {:ok, _reviewed} = Plans.review_plan(old_plan, old_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(old_plan, %{status: :passed})

    old_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(-720 * 24 * 60 * 60, :second)

    Repo.update_all(
      from(plan in Plan, where: plan.id == ^old_plan.id),
      set: [inserted_at: old_time, updated_at: old_time]
    )

    Repo.update_all(
      from(run in ValidationRun, where: run.plan_id == ^old_plan.id),
      set: [inserted_at: old_time, updated_at: old_time, completed_at: old_time]
    )

    old_score = Reputation.trust_score_for_user(old_user).overall

    assert recent_score > old_score
  end
end
