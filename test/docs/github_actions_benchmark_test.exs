defmodule Micelio.Docs.GitHubActionsBenchmarkTest do
  use ExUnit.Case, async: true

  test "benchmark doc captures required sections" do
    path = Path.expand("../../docs/benchmarks/github_actions_vs_ephemeral_vms.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(
             contents,
             "# GitHub Actions vs Ephemeral VM Cost and Performance Benchmark"
           )

    assert String.contains?(contents, "## Metrics to Capture")
    assert String.contains?(contents, "## Cost Model Inputs")
    assert String.contains?(contents, "## Decision Criteria")
    assert String.contains?(contents, "## Next Steps")
  end
end
