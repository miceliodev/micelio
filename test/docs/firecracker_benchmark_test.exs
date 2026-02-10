defmodule Micelio.Docs.FirecrackerBenchmarkTest do
  use ExUnit.Case, async: true

  test "benchmark plan captures required sections" do
    path = Path.expand("../../docs/benchmarks/firecracker_vs_containers.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(contents, "# Firecracker vs Containers Benchmark Plan")
    assert String.contains?(contents, "## Workload Matrix")
    assert String.contains?(contents, "## Metrics to Capture")
    assert String.contains?(contents, "## Next Steps")
  end
end
