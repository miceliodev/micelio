defmodule Micelio.ContributionConfidence do
  @moduledoc """
  Calculates confidence scores for plan contributions.
  """

  import Ecto.Query, warn: false

  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.Reputation
  alias Micelio.ValidationEnvironments.ValidationRun

  @default_validation_score 50
  @default_reputation_score 50
  @default_token_efficiency_score 50
  @default_token_baseline 2000
  @default_weights %{validation: 0.5, reputation: 0.3, token_efficiency: 0.2}
  @default_auto_accept_threshold 60

  defmodule Score do
    @moduledoc false
    defstruct [:overall, :components, :label]
  end

  def score_for_plan(%Plan{} = plan, opts \\ []) do
    validation_score = validation_score(plan, opts)
    reputation_score = reputation_score(plan, opts)
    token_efficiency_score = token_efficiency_score(plan.token_count, opts)

    weights = resolve_weights(opts)

    overall =
      weighted_average(
        [validation_score, reputation_score, token_efficiency_score],
        [weights.validation, weights.reputation, weights.token_efficiency]
      )

    %Score{
      overall: overall,
      components: %{
        validation: validation_score,
        reputation: reputation_score,
        token_efficiency: token_efficiency_score
      },
      label: label_for_score(overall)
    }
  end

  def auto_accept?(%Score{} = score, opts \\ []) do
    threshold = resolve_auto_accept_threshold(opts)
    score.overall >= threshold
  end

  def scores_for_plans(plans, opts \\ []) when is_list(plans) do
    runs_by_plan = latest_runs_by_plan(plans)
    reputation_by_user_id = reputations_by_user_id(plans, opts)

    plans
    |> Map.new(fn plan ->
      reputation = Map.get(reputation_by_user_id, plan.user_id)

      score =
        score_for_plan(plan,
          validation_run: Map.get(runs_by_plan, plan.id),
          reputation: reputation
        )

      {plan.id, score}
    end)
  end

  def label_for_score(score) when is_integer(score) do
    cond do
      score >= 80 -> "High"
      score >= 60 -> "Medium"
      true -> "Low"
    end
  end

  def label_for_score(_score), do: "Unknown"

  defp validation_score(plan, opts) do
    case Keyword.get(opts, :validation_score) do
      score when is_integer(score) -> clamp_score(score)
      _ -> validation_score_from_run(resolve_validation_run(plan, opts))
    end
  end

  defp validation_score_from_run(nil), do: @default_validation_score

  defp validation_score_from_run(%ValidationRun{metrics: metrics}) do
    metrics
    |> quality_score_from_metrics()
    |> fallback_score(@default_validation_score)
    |> clamp_score()
  end

  defp reputation_score(%Plan{} = plan, opts) do
    case Keyword.get(opts, :reputation) do
      %Reputation.Score{overall: score} -> clamp_score(score)
      score when is_integer(score) -> clamp_score(score)
      _ -> reputation_from_plan(plan)
    end
  end

  defp reputation_from_plan(%Plan{user: %Micelio.Accounts.User{} = user}) do
    user
    |> Reputation.trust_score_for_user()
    |> Map.get(:overall, @default_reputation_score)
    |> clamp_score()
  end

  defp reputation_from_plan(_plan), do: @default_reputation_score

  defp token_efficiency_score(nil, _opts), do: @default_token_efficiency_score

  defp token_efficiency_score(token_count, opts)
       when is_integer(token_count) and token_count >= 0 do
    baseline = resolve_token_baseline(opts)

    score =
      case baseline do
        value when is_number(value) and value > 0 ->
          baseline / (baseline + token_count) * 100

        _ ->
          @default_token_efficiency_score
      end

    score
    |> Float.round(0)
    |> trunc()
    |> clamp_score()
  end

  defp token_efficiency_score(_token_count, _opts), do: @default_token_efficiency_score

  defp resolve_validation_run(%Plan{} = plan, opts) do
    case Keyword.get(opts, :validation_run) || List.first(Keyword.get(opts, :validation_runs, [])) do
      %ValidationRun{} = run ->
        run

      _ ->
        ValidationRun
        |> where([run], run.plan_id == ^plan.id)
        |> order_by([run], desc: run.completed_at, desc: run.inserted_at)
        |> limit(1)
        |> Repo.one()
    end
  end

  defp latest_runs_by_plan([]), do: %{}

  defp latest_runs_by_plan(plans) do
    ids = Enum.map(plans, & &1.id)

    ValidationRun
    |> where([run], run.plan_id in ^ids)
    |> order_by([run], desc: run.completed_at, desc: run.inserted_at)
    |> distinct([run], run.plan_id)
    |> select([run], {run.plan_id, run})
    |> Repo.all()
    |> Map.new()
  end

  defp reputations_by_user_id(plans, opts) do
    case Keyword.get(opts, :reputation_by_user_id) do
      %{} = map -> map
      _ -> compute_reputations_by_user_id(plans)
    end
  end

  defp compute_reputations_by_user_id(plans) do
    plans
    |> Enum.filter(& &1.user)
    |> Enum.uniq_by(& &1.user_id)
    |> Map.new(fn plan ->
      {plan.user_id, Reputation.trust_score_for_user(plan.user)}
    end)
  end

  defp resolve_weights(opts) do
    config_weights =
      :micelio
      |> Application.get_env(:contribution_confidence, [])
      |> Keyword.get(:weights, %{})

    override = Keyword.get(opts, :weights, %{})

    Map.merge(@default_weights, config_weights)
    |> Map.merge(override)
  end

  defp resolve_token_baseline(opts) do
    config_baseline =
      :micelio
      |> Application.get_env(:contribution_confidence, [])
      |> Keyword.get(:token_baseline, @default_token_baseline)

    Keyword.get(opts, :token_baseline, config_baseline)
  end

  defp resolve_auto_accept_threshold(opts) do
    config_threshold =
      :micelio
      |> Application.get_env(:contribution_confidence, [])
      |> Keyword.get(:auto_accept_threshold, @default_auto_accept_threshold)

    Keyword.get(opts, :auto_accept_threshold, config_threshold)
  end

  defp quality_score_from_metrics(nil), do: nil

  defp quality_score_from_metrics(metrics) when is_map(metrics) do
    Map.get(metrics, "quality_score") || Map.get(metrics, :quality_score)
  end

  defp quality_score_from_metrics(_metrics), do: nil

  defp fallback_score(nil, default), do: default
  defp fallback_score(value, _default), do: value

  defp weighted_average(scores, weights) do
    total_weight = Enum.sum(weights)

    if total_weight == 0 do
      0
    else
      scores
      |> Enum.zip(weights)
      |> Enum.reduce(0.0, fn {score, weight}, acc -> acc + score * weight end)
      |> Kernel./(total_weight)
      |> Float.round(0)
      |> trunc()
      |> clamp_score()
    end
  end

  defp clamp_score(score) when is_integer(score) do
    score
    |> max(0)
    |> min(100)
  end

  defp clamp_score(score) when is_number(score) do
    score
    |> Float.round(0)
    |> trunc()
    |> clamp_score()
  end

  defp clamp_score(_score), do: 0
end
