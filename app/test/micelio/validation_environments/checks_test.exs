defmodule Micelio.ValidationEnvironments.ChecksTest do
  use ExUnit.Case, async: true

  alias Micelio.ValidationEnvironments.Checks

  test "enforces minimum coverage delta thresholds" do
    checks = Checks.default_checks()

    assert {:ok, results} =
             Checks.run(checks, Micelio.TestValidationExecutor, :instance_ref,
               min_coverage_delta: 0.02
             )

    assert results.coverage_delta == 0.03

    assert {:error, results} =
             Checks.run(checks, Micelio.TestValidationExecutor, :instance_ref,
               min_coverage_delta: 0.05
             )

    assert results.coverage_delta == 0.03
  end

  test "includes quality gate checks for linting, security, and performance" do
    checks = Checks.default_checks()
    ids = Enum.map(checks, & &1.id)
    kinds = Enum.map(checks, & &1.kind)

    assert "credo" in ids
    assert "dialyzer" in ids
    assert "semgrep" in ids
    assert "sobelow" in ids
    assert "e2e" in ids
    assert "performance_baseline" in ids
    assert :lint in kinds
    assert :security in kinds
    assert :performance in kinds
    assert :e2e in kinds
  end
end
