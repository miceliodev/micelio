defmodule Mix.Tasks.Micelio.Performance.Baseline do
  @shortdoc "Validates Micelio performance baselines"

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} =
      OptionParser.parse(args, switches: [mode: :string, path: :string])

    mode = opts[:mode] || "validate"
    path = opts[:path]
    baseline_opts = if path, do: [path: path], else: []

    case mode do
      "validate" ->
        run_validation(baseline_opts)

      _ ->
        Mix.raise("Unknown mode #{inspect(mode)}. Use --mode validate.")
    end
  end

  defp run_validation(opts) do
    case Micelio.PerformanceBaseline.run(opts) do
      {:ok, payload} ->
        print_results(payload.results, payload.baseline_path)
        Mix.shell().info("Performance baseline validated.")

      {:error, payload} ->
        print_results(payload.results, payload.baseline_path)
        Mix.raise("Performance baseline regression detected.")
    end
  end

  defp print_results(results, baseline_path) do
    Mix.shell().info("Baseline: #{baseline_path}")

    Enum.each(results, fn result ->
      Mix.shell().info(
        "#{result["label"]}: #{result["duration_ms"]}ms (max #{result["max_ms"]}ms) - #{result["status"]}"
      )
    end)
  end
end
