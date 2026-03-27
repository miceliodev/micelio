defmodule Mix.Tasks.Micelio.Sapling.IntegrationDesign do
  @shortdoc "Generates the Sapling integration layer design report"

  @moduledoc """
  Generates the Sapling integration layer design report.

      mix micelio.sapling.integration_design --output docs/benchmarks/sapling_integration_layer.md
  """

  use Mix.Task

  alias Micelio.Sapling.IntegrationDesign

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output: :string, started_at: :string]
      )

    output_path = Keyword.get(opts, :output, "docs/benchmarks/sapling_integration_layer.md")
    started_at = parse_started_at(Keyword.get(opts, :started_at))
    report = IntegrationDesign.build_report(started_at: started_at)
    content = IntegrationDesign.format_markdown(report)

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, content)
    Mix.shell().info("Wrote integration layer design report to #{output_path}")
  end

  defp parse_started_at(nil), do: DateTime.utc_now()

  defp parse_started_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> Mix.raise("Invalid --started-at value: #{inspect(reason)}")
    end
  end
end
