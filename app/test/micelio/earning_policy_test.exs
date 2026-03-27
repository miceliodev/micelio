defmodule Micelio.EarningPolicyTest do
  use ExUnit.Case, async: true

  alias Micelio.AITokens.EarningPolicy

  test "plan_reward clamps to min and max" do
    assert EarningPolicy.plan_reward(0) == 25
    assert EarningPolicy.plan_reward(1000) == 100
    assert EarningPolicy.plan_reward(10_000) == 500
    assert EarningPolicy.plan_reward(nil) == 25
  end

  test "plan_suggestion_reward requires minimum length" do
    assert EarningPolicy.plan_suggestion_reward("Too short") == 0

    suggestion = String.duplicate("Add acceptance criteria and edge cases. ", 4)
    assert EarningPolicy.plan_suggestion_reward(suggestion) == 26
  end

  test "plan_suggestion_reward includes the minimum length threshold" do
    suggestion = String.duplicate("a", 120)

    assert EarningPolicy.plan_suggestion_reward(suggestion) == 20
  end

  test "plan_suggestion_reward clamps to max" do
    suggestion = String.duplicate("Helpful suggestion. ", 100)
    assert EarningPolicy.plan_suggestion_reward(suggestion) == 75
  end

  test "rules expose active and planned mechanics" do
    rules = EarningPolicy.rules()

    active_keys = Enum.map(rules.active, & &1.key)
    planned_keys = Enum.map(rules.planned, & &1.key)

    assert :plan_accepted in active_keys
    assert :plan_suggestion_submitted in active_keys
    assert :session_landed in planned_keys
  end
end
