defmodule Micelio.PerformanceBaselineTest do
  use ExUnit.Case, async: true

  alias Micelio.PerformanceBaseline

  test "passes when benchmarks meet baseline thresholds" do
    path = write_baseline(10_000)

    assert {:ok, result} = PerformanceBaseline.run(path: path)
    assert Enum.all?(result.results, &(&1["status"] == "passed"))
  end

  test "fails when benchmarks exceed baseline thresholds" do
    path = write_baseline(0)

    assert {:error, result} = PerformanceBaseline.run(path: path)
    assert Enum.any?(result.results, &(&1["status"] == "failed"))
  end

  defp write_baseline(max_ms) do
    path =
      Path.join(
        System.tmp_dir!(),
        "micelio-performance-baseline-#{System.unique_integer([:positive])}.json"
      )

    baseline = %{
      "version" => 1,
      "benchmarks" => [
        %{"id" => "json_encode", "max_ms" => max_ms},
        %{"id" => "map_build", "max_ms" => max_ms},
        %{"id" => "string_concat", "max_ms" => max_ms}
      ]
    }

    File.write!(path, Jason.encode!(baseline))
    path
  end
end
