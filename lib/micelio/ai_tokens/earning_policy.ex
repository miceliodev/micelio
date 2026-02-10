defmodule Micelio.AITokens.EarningPolicy do
  @moduledoc """
  Defines earn-by-contributing mechanics for AI tokens.

  Active rules are used by the application today. Planned rules capture the
  intended mechanics for future contribution types so UI and docs stay aligned.
  """

  @prompt_request_reward_rate 0.1
  @prompt_request_reward_min 25
  @prompt_request_reward_max 500

  @prompt_suggestion_reward_min_length 120
  @prompt_suggestion_reward_divisor 6
  @prompt_suggestion_reward_min 15
  @prompt_suggestion_reward_max 75

  @active_rules [
    %{
      key: :prompt_request_accepted,
      title: "Landed prompt request",
      description: "Rewards accepted prompt requests based on token usage.",
      formula: "round(tokens_used * 0.1), clamped to 25..500"
    },
    %{
      key: :prompt_suggestion_submitted,
      title: "Prompt review",
      description: "Rewards thorough prompt suggestions based on length.",
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

  def prompt_request_reward(token_count) when is_integer(token_count) do
    token_count
    |> Kernel.*(@prompt_request_reward_rate)
    |> Float.round(0)
    |> trunc()
    |> clamp(@prompt_request_reward_min, @prompt_request_reward_max)
  end

  def prompt_request_reward(nil), do: prompt_request_reward(0)

  def prompt_suggestion_reward(suggestion) do
    suggestion_length =
      suggestion
      |> to_string()
      |> String.trim()
      |> String.length()

    if suggestion_length < @prompt_suggestion_reward_min_length do
      0
    else
      suggestion_length
      |> div(@prompt_suggestion_reward_divisor)
      |> clamp(@prompt_suggestion_reward_min, @prompt_suggestion_reward_max)
    end
  end

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end
end
