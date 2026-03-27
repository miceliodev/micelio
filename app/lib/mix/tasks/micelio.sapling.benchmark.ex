defmodule Mix.Tasks.Micelio.Sapling.Benchmark do
  @shortdoc "Benchmarks Sapling against Git for Micelio workflows"

  @moduledoc """
  Benchmarks Sapling against Git for Micelio workflows.

      mix micelio.sapling.benchmark --repo /path/to/repo --runs 5 --output docs/benchmarks/sapling_vs_git.md

  If Sapling is not available yet, pass `--allow-missing` to run benchmarks
  with the remaining tools and record the missing executables in the report.
  """

  use Mix.Task

  alias Micelio.Sapling.Benchmark

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          runs: :integer,
          output: :string,
          tools: :string,
          allow_missing: :boolean
        ]
      )

    repo_path = Keyword.get(opts, :repo, File.cwd!())
    runs = Keyword.get(opts, :runs, 5)
    output_path = Keyword.get(opts, :output, "docs/benchmarks/sapling_vs_git.md")

    tools =
      case Benchmark.parse_tools(Keyword.get(opts, :tools)) do
        {:ok, tools} -> tools
        {:error, reason} -> Mix.raise("Invalid tools list: #{inspect(reason)}")
      end

    allow_missing = Keyword.get(opts, :allow_missing, false)
    availability = Benchmark.tool_availability(tools)

    if availability.missing != [] and not allow_missing do
      Mix.raise("Missing tools: #{Enum.join(availability.missing, ", ")}")
    end

    if availability.available == [] do
      Mix.raise("No benchmark tools available after filtering missing executables.")
    end

    case Benchmark.ensure_repo(repo_path) do
      :ok -> :ok
      {:error, :not_a_repo} -> Mix.raise("Not a Git/Sapling repo: #{repo_path}")
    end

    {:ok, report} = Benchmark.run(repo_path, runs: runs, tools: availability.available)
    summary = Benchmark.summarize(report.results)
    tool_versions = Benchmark.tool_versions(availability.available)

    report =
      report
      |> Map.put(:missing_tools, availability.missing)
      |> Map.put(:tool_versions, tool_versions)

    content = Benchmark.format_markdown(report, summary)

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, content)
    Mix.shell().info("Wrote benchmark report to #{output_path}")
  end
end
