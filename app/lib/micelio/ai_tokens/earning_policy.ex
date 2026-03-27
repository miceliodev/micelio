defmodule Micelio.AITokens.EarningPolicy do
  @moduledoc """
  Defines earn-by-contributing mechanics for AI tokens.

  Active rules are used by the application today. Planned rules capture the
  intended mechanics for future contribution types so UI and docs stay aligned.
  """

  @plan_reward_rate 0.1
  @plan_reward_min 25
  @plan_reward_max 500

  @plan_suggestion_reward_min_length 120
  @plan_suggestion_reward_divisor 6
  @plan_suggestion_reward_min 15
  @plan_suggestion_reward_max 75

  @active_rules [
    %{
      key: :plan_accepted,
      title: "Landed plan",
      description: "Rewards accepted plans based on token usage.",
      formula: "round(tokens_used * 0.1), clamped to 25..500"
    },
    %{
      key: :plan_suggestion_submitted,
      title: "Plan review",
      description: "Rewards thorough plan suggestions based on length.",
      formula: "length / 6, clamped to 15..75 (min length 120 chars)"
    }
  ]

  @planned_rules [
    %{
      key: :session_landed,
      title: "Landed session",
      description: "Reward merged sessions with a base plus per-change credit.",
      formula: "base 40 + (changes * 3), clamped to 25..400"
    },
    %{
      key: :bug_report_verified,
      title: "Verified bug report",
      description: "Reward confirmed bugs based on severity.",
      formula: "low 15, medium 35, high 75, critical 120"
    },
    %{
      key: :community_helpful_answer,
      title: "Community help",
      description: "Reward accepted answers and maintainer-endorsed help.",
      formula: "base 10 + maintainer bonus 10"
    }
  ]

  def rules do
    %{active: @active_rules, planned: @planned_rules}
  end

  def plan_reward(token_count) when is_integer(token_count) do
    token_count
    |> Kernel.*(@plan_reward_rate)
    |> Float.round(0)
    |> trunc()
    |> clamp(@plan_reward_min, @plan_reward_max)
  end

  def plan_reward(nil), do: plan_reward(0)

  def plan_suggestion_reward(suggestion) do
    suggestion_length =
      suggestion
      |> to_string()
      |> String.trim()
      |> String.length()

    if suggestion_length < @plan_suggestion_reward_min_length do
      0
    else
      suggestion_length
      |> div(@plan_suggestion_reward_divisor)
      |> clamp(@plan_suggestion_reward_min, @plan_suggestion_reward_max)
    end
  end

  def prompt_suggestion_reward(suggestion), do: plan_suggestion_reward(suggestion)

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end
end
