defmodule Micelio.Reputation do
  @moduledoc """
  Calculates trust scores for contributors.
  """

  import Ecto.Query, warn: false

  alias Micelio.Accounts.User
  alias Micelio.Plans.Plan
  alias Micelio.Plans.PlanSuggestion
  alias Micelio.Repo
  alias Micelio.Sessions.Session
  alias Micelio.ValidationEnvironments.ValidationRun

  @types [:docs, :tests, :features, :fixes]
  @half_life_days 180
  @volume_target 8.0

  defmodule Score do
    @moduledoc false
    defstruct [:overall, :by_type, :metrics]
  end

  def trust_score_for_user(%User{} = user) do
    plans = list_plans(user)
    sessions = list_sessions(user)

    suggestion_counts = plan_suggestion_counts(plans)
    validation_stats = validation_stats(plans)

    contributions =
      build_contributions(plans, sessions, suggestion_counts, validation_stats)

    overall_metrics = metrics_for_contributions(contributions, validation_stats.all)

    by_type =
      @types
      |> Map.new(fn type ->
        type_contributions = Enum.filter(contributions, &(&1.type == type))
        type_validations = Map.get(validation_stats.by_type, type, %{passed: [], total: []})
        {type, score_for_metrics(metrics_for_contributions(type_contributions, type_validations))}
      end)

    %Score{
      overall: score_for_metrics(overall_metrics),
      by_type: by_type,
      metrics: overall_metrics
    }
  end

  def types, do: @types

  defp list_plans(%User{} = user) do
    Plan
    |> where([plan], plan.user_id == ^user.id)
    |> select([plan], %{
      id: plan.id,
      title: plan.title,
      prompt: plan.prompt,
      review_status: plan.review_status,
      inserted_at: plan.inserted_at
    })
    |> Repo.all()
  end

  defp list_sessions(%User{} = user) do
    Session
    |> where([session], session.user_id == ^user.id)
    |> select([session], %{
      id: session.id,
      goal: session.goal,
      status: session.status,
      inserted_at: session.inserted_at,
      landed_at: session.landed_at
    })
    |> Repo.all()
  end

  defp plan_suggestion_counts(plans) do
    plan_ids = Enum.map(plans, & &1.id)

    if plan_ids == [] do
      %{}
    else
      PlanSuggestion
      |> where([suggestion], suggestion.plan_id in ^plan_ids)
      |> group_by([suggestion], suggestion.plan_id)
      |> select([suggestion], {suggestion.plan_id, count(suggestion.id)})
      |> Repo.all()
      |> Map.new()
    end
  end

  defp validation_stats(plans) do
    plan_ids = Enum.map(plans, & &1.id)

    runs =
      if plan_ids == [] do
        []
      else
        ValidationRun
        |> where([run], run.plan_id in ^plan_ids)
        |> where([run], run.status in [:passed, :failed])
        |> select([run], %{
          plan_id: run.plan_id,
          status: run.status,
          completed_at: run.completed_at,
          inserted_at: run.inserted_at
        })
        |> Repo.all()
      end

    by_plan =
      runs
      |> Enum.group_by(& &1.plan_id)
      |> Map.new(fn {id, entries} -> {id, entries} end)

    by_type =
      plans
      |> Enum.group_by(&classify_plan/1)
      |> Map.new(fn {type, requests} ->
        request_ids = MapSet.new(Enum.map(requests, & &1.id))

        type_runs = Enum.filter(runs, &MapSet.member?(request_ids, &1.plan_id))

        {type,
         %{
           passed: Enum.filter(type_runs, &(&1.status == :passed)),
           total: type_runs
         }}
      end)

    %{
      by_plan: by_plan,
      by_type: by_type,
      all: %{passed: Enum.filter(runs, &(&1.status == :passed)), total: runs}
    }
  end

  defp build_contributions(plans, sessions, suggestion_counts, validation_stats) do
    plan_contributions =
      Enum.map(plans, fn plan ->
        validations = Map.get(validation_stats.by_plan, plan.id, [])
        passed_validation = Enum.any?(validations, &(&1.status == :passed))

        %{
          id: plan.id,
          type: classify_plan(plan),
          kind: :plan,
          status: plan.review_status,
          occurred_at: plan.inserted_at,
          review_iterations: Map.get(suggestion_counts, plan.id, 0),
          passed_validation: passed_validation
        }
      end)

    session_contributions =
      Enum.map(sessions, fn session ->
        occurred_at = session.landed_at || session.inserted_at

        %{
          id: session.id,
          type: classify_session(session),
          kind: :session,
          status: session.status,
          occurred_at: occurred_at,
          review_iterations: 0,
          passed_validation: false
        }
      end)

    plan_contributions ++ session_contributions
  end

  defp metrics_for_contributions(contributions, validation_stats) do
    now = DateTime.utc_now()

    contributions =
      Enum.filter(contributions, fn contribution ->
        contribution.occurred_at != nil
      end)

    weighted_contributions =
      Enum.map(contributions, fn contribution ->
        Map.put(contribution, :weight, decay_weight(contribution.occurred_at, now))
      end)

    totals = count_weighted_contributions(weighted_contributions)

    review_metrics = review_metrics(weighted_contributions)

    validation_metrics =
      validation_metrics(validation_stats, now)

    %{
      total_weight: totals.total_weight,
      landed_weight: totals.landed_weight,
      rejected_weight: totals.rejected_weight,
      landed_rate: totals.landed_rate,
      review_iteration_score: review_metrics.score,
      review_iteration_avg: review_metrics.average,
      rejected_after_validation_rate: totals.rejected_after_validation_rate,
      validation_pass_rate: validation_metrics.pass_rate,
      volume_score: volume_score(totals.total_weight)
    }
  end

  defp score_for_metrics(%{total_weight: +0.0}), do: 0

  defp score_for_metrics(metrics) do
    base =
      0.35 * metrics.landed_rate +
        0.35 * metrics.validation_pass_rate +
        0.2 * metrics.review_iteration_score +
        0.1 * metrics.volume_score

    penalty = 0.2 * metrics.rejected_after_validation_rate

    score = max(0.0, base - penalty)
    score |> Kernel.*(100) |> Float.round(0) |> trunc()
  end

  defp count_weighted_contributions(contributions) do
    finished =
      Enum.filter(contributions, fn contribution ->
        contribution.status in [:accepted, :rejected, "landed", "abandoned"]
      end)

    landed_weight =
      Enum.reduce(finished, 0.0, fn contribution, acc ->
        case contribution.status do
          :accepted -> acc + contribution.weight
          "landed" -> acc + contribution.weight
          _ -> acc
        end
      end)

    rejected_weight =
      Enum.reduce(finished, 0.0, fn contribution, acc ->
        case contribution.status do
          :rejected -> acc + contribution.weight
          "abandoned" -> acc + contribution.weight
          _ -> acc
        end
      end)

    total_weight = Enum.reduce(finished, 0.0, &(&1.weight + &2))

    rejected_after_validation_weight =
      Enum.reduce(finished, 0.0, fn contribution, acc ->
        if contribution.status == :rejected and contribution.passed_validation do
          acc + contribution.weight
        else
          acc
        end
      end)

    %{
      total_weight: total_weight,
      landed_weight: landed_weight,
      rejected_weight: rejected_weight,
      landed_rate: rate(landed_weight, total_weight),
      rejected_after_validation_rate: rate(rejected_after_validation_weight, total_weight)
    }
  end

  defp review_metrics(contributions) do
    plan_contributions = Enum.filter(contributions, &(&1.kind == :plan))

    weighted_total = Enum.reduce(plan_contributions, 0.0, &(&1.weight + &2))

    weighted_iterations =
      Enum.reduce(plan_contributions, 0.0, fn contribution, acc ->
        acc + contribution.weight * contribution.review_iterations
      end)

    average = rate(weighted_iterations, weighted_total)

    %{
      average: average,
      score: if(weighted_total > 0, do: 1.0 / (1.0 + average), else: 0.0)
    }
  end

  defp validation_metrics(%{passed: passed, total: total}, now) do
    weighted_total = Enum.reduce(total, 0.0, &(&2 + decay_weight(run_occurred_at(&1), now)))

    weighted_passed =
      Enum.reduce(passed, 0.0, &(&2 + decay_weight(run_occurred_at(&1), now)))

    pass_rate = if weighted_total > 0, do: weighted_passed / weighted_total, else: 0.4

    %{pass_rate: pass_rate}
  end

  defp volume_score(total_weight) do
    min(1.0, total_weight / @volume_target)
  end

  defp rate(_numerator, +0.0), do: +0.0
  defp rate(numerator, denominator), do: numerator / denominator

  defp decay_weight(%DateTime{} = occurred_at, now) do
    days = DateTime.diff(now, occurred_at, :day)
    :math.exp(-days / @half_life_days)
  end

  defp decay_weight(%NaiveDateTime{} = occurred_at, now) do
    decay_weight(DateTime.from_naive!(occurred_at, "Etc/UTC"), now)
  end

  defp decay_weight(_, _now), do: 0.0

  defp run_occurred_at(%{completed_at: %DateTime{} = completed_at}), do: completed_at
  defp run_occurred_at(%{inserted_at: %DateTime{} = inserted_at}), do: inserted_at
  defp run_occurred_at(_), do: DateTime.utc_now()

  defp classify_plan(%{title: title, prompt: prompt}) do
    classify_text([title, prompt])
  end

  defp classify_session(%{goal: goal}) do
    classify_text([goal])
  end

  defp classify_text(texts) do
    content =
      texts
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> String.downcase()

    cond do
      String.contains?(content, ["doc", "readme", "documentation"]) -> :docs
      String.contains?(content, ["test", "spec", "coverage"]) -> :tests
      String.contains?(content, ["fix", "bug", "error", "issue"]) -> :fixes
      true -> :features
    end
  end
end
