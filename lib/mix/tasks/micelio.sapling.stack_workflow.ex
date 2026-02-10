defmodule Mix.Tasks.Micelio.Sapling.StackWorkflow do
  @shortdoc "Simulates stacked agent sessions in Git/Sapling and writes a report"

  @moduledoc """
  Simulates stacked agent sessions in Git/Sapling and writes a report.

      mix micelio.sapling.stack_workflow --sessions 3 --output docs/benchmarks/sapling_stack_workflow.md

  If Sapling is not available yet, pass `--allow-missing` to run the simulation
  with the remaining tools and record missing executables in the report.
  """

  use Mix.Task

  alias Micelio.Sapling.StackWorkflow

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          sessions: :integer,
          output: :string,
          tools: :string,
          allow_missing: :boolean,
          keep_repo: :boolean
        ]
      )

    sessions = Keyword.get(opts, :sessions, 3)
    output_path = Keyword.get(opts, :output, "docs/benchmarks/sapling_stack_workflow.md")

    tools =
      case StackWorkflow.parse_tools(Keyword.get(opts, :tools)) do
        {:ok, tools} -> tools
        {:error, reason} -> Mix.raise("Invalid tools list: #{inspect(reason)}")
      end

    allow_missing = Keyword.get(opts, :allow_missing, false)
    availability = StackWorkflow.tool_availability(tools)

    if availability.missing != [] and not allow_missing do
      Mix.raise("Missing tools: #{Enum.join(availability.missing, ", ")}")
    end

    if availability.available == [] do
      Mix.raise("No stack workflow tools available after filtering missing executables.")
    end

    {:ok, report} =
      StackWorkflow.run(
        tools: availability.available,
        sessions: sessions,
        cleanup: not Keyword.get(opts, :keep_repo, false)
      )

    report =
      report
      |> Map.put(:missing_tools, availability.missing)

    content = StackWorkflow.format_markdown(report)

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, content)
    Mix.shell().info("Wrote stacking workflow report to #{output_path}")
  end
end
