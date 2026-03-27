defmodule Mix.Tasks.Micelio.Sapling.Interoperability do
  @shortdoc "Evaluates Sapling/Git interoperability for gradual migration"

  @moduledoc """
  Evaluates Sapling/Git interoperability for gradual migration.

      mix micelio.sapling.interoperability --output docs/benchmarks/sapling_git_interoperability.md

  If Sapling is not available yet, pass `--allow-missing` to run the evaluation
  with the remaining tools and record missing executables in the report.
  """

  use Mix.Task

  alias Micelio.Sapling.Interoperability

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output: :string, tools: :string, allow_missing: :boolean]
      )

    output_path = Keyword.get(opts, :output, "docs/benchmarks/sapling_git_interoperability.md")

    tools =
      case Interoperability.parse_tools(Keyword.get(opts, :tools)) do
        {:ok, tools} -> tools
        {:error, reason} -> Mix.raise("Invalid tools list: #{inspect(reason)}")
      end

    allow_missing = Keyword.get(opts, :allow_missing, false)
    availability = Interoperability.tool_availability(tools)

    if availability.missing != [] and not allow_missing do
      Mix.raise("Missing tools: #{Enum.join(availability.missing, ", ")}")
    end

    if availability.available == [] do
      Mix.raise("No interoperability tools available after filtering missing executables.")
    end

    {:ok, report} = Interoperability.run(tools: tools)
    tool_versions = Interoperability.tool_versions(availability.available)

    report =
      report
      |> Map.put(:missing_tools, availability.missing)
      |> Map.put(:available_tools, availability.available)
      |> Map.put(:tool_versions, tool_versions)

    content = Interoperability.format_markdown(report)

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, content)
    Mix.shell().info("Wrote interoperability report to #{output_path}")
  end
end
