defmodule Micelio.PerformanceBaseline do
  @moduledoc """
  Runs small, deterministic benchmarks and compares them against stored baselines.
  """

  @default_baseline_path Path.expand("priv/performance_baseline.json")

  def run(opts \\ []) do
    baseline_path = Keyword.get(opts, :path, @default_baseline_path)
    baseline = load_baseline(baseline_path)

    results =
      Enum.map(benchmarks(), fn benchmark ->
        max_ms = Map.get(baseline, benchmark.id, benchmark.max_ms)
        duration_ms = measure_ms(benchmark.fun)
        status = if duration_ms <= max_ms, do: "passed", else: "failed"

        %{
          "id" => benchmark.id,
          "label" => benchmark.label,
          "duration_ms" => duration_ms,
          "max_ms" => max_ms,
          "status" => status
        }
      end)

    payload = %{baseline_path: baseline_path, results: results}

    if Enum.all?(results, &(&1["status"] == "passed")) do
      {:ok, payload}
    else
      {:error, payload}
    end
  end

  defp benchmarks do
    [
      %{id: "json_encode", label: "JSON encode 1k entries", max_ms: 500, fun: &benchmark_json/0},
      %{id: "map_build", label: "Map build 50k entries", max_ms: 500, fun: &benchmark_map/0},
      %{
        id: "string_concat",
        label: "String concat 10k entries",
        max_ms: 500,
        fun: &benchmark_string/0
      }
    ]
  end

  defp load_baseline(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, %{"benchmarks" => benchmarks}} <- Jason.decode(contents) do
      Map.new(benchmarks, fn %{"id" => id, "max_ms" => max_ms} ->
        {id, max_ms}
      end)
    else
      _ -> %{}
    end
  end

  defp measure_ms(fun) do
    started_at = System.monotonic_time(:microsecond)
    fun.()
    finished_at = System.monotonic_time(:microsecond)
    div(finished_at - started_at, 1000)
  end

  defp benchmark_json do
    data = for i <- 1..1_000, into: %{}, do: {Integer.to_string(i), i}
    Jason.encode!(data)
    :ok
  end

  defp benchmark_map do
    Enum.reduce(1..50_000, %{}, fn i, acc -> Map.put(acc, i, i) end)
    :ok
  end

  defp benchmark_string do
    Enum.map_join(1..10_000, "-", &Integer.to_string/1)
    :ok
  end
end
