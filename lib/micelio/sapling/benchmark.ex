defmodule Micelio.Sapling.Benchmark do
  @moduledoc """
  Benchmarks Sapling against Git for Micelio workflows.
  """

  @type tool :: :git | :sapling
  @type scenario :: %{
          id: atom(),
          description: String.t(),
          commands: %{tool() => {String.t(), [String.t()]}}
        }

  @default_scenarios [
    %{
      id: :status,
      description: "Working tree status",
      commands: %{git: {"git", ["status", "--short"]}, sapling: {"sl", ["status"]}}
    },
    %{
      id: :log,
      description: "Recent history",
      commands: %{
        git: {"git", ["log", "-n", "200", "--oneline"]},
        sapling: {"sl", ["log", "-l", "200"]}
      }
    },
    %{
      id: :diff,
      description: "Working tree diff",
      commands: %{git: {"git", ["diff", "--stat"]}, sapling: {"sl", ["diff", "--stat"]}}
    },
    %{
      id: :files,
      description: "List tracked files",
      commands: %{git: {"git", ["ls-files"]}, sapling: {"sl", ["files"]}}
    }
  ]

  @spec build_scenarios() :: [scenario()]
  def build_scenarios do
    @default_scenarios
  end

  @spec parse_tools(nil | String.t() | [tool()]) :: {:ok, [tool()]} | {:error, term()}
  def parse_tools(nil), do: {:ok, [:git, :sapling]}

  def parse_tools(tools) when is_list(tools) do
    normalized =
      tools
      |> Enum.map(&normalize_tool/1)
      |> Enum.reject(&is_nil/1)

    if length(normalized) == length(tools) and normalized != [] do
      {:ok, normalized}
    else
      {:error, {:unknown_tools, tools}}
    end
  end

  def parse_tools(tools) when is_binary(tools) do
    tools
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&normalize_tool/1)
    |> case do
      [] ->
        {:error, {:unknown_tools, tools}}

      normalized ->
        if Enum.any?(normalized, &is_nil/1) do
          {:error, {:unknown_tools, tools}}
        else
          {:ok, normalized}
        end
    end
  end

  @spec ensure_tools([tool()], keyword()) :: :ok | {:error, term()}
  def ensure_tools(tools, opts \\ []) do
    availability = tool_availability(tools, opts)

    case availability.missing do
      [] -> :ok
      _ -> {:error, {:missing_tools, availability.missing}}
    end
  end

  @spec tool_availability([tool()], keyword()) :: %{available: [tool()], missing: [tool()]}
  def tool_availability(tools, opts \\ []) do
    finder = Keyword.get(opts, :finder, &System.find_executable/1)

    {available, missing} =
      Enum.split_with(tools, fn tool ->
        tool
        |> tool_command()
        |> finder.()
      end)

    %{available: available, missing: missing}
  end

  @spec tool_versions([tool()], keyword()) :: %{tool() => String.t()}
  def tool_versions(tools, opts \\ []) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    tools
    |> Map.new(fn tool ->
      {output, status} = runner.(tool_command(tool), ["--version"], [])

      version =
        output
        |> to_string()
        |> String.trim()
        |> case do
          "" -> "unknown"
          value -> value
        end

      version = if status == 0, do: version, else: "unknown"

      {tool, version}
    end)
  end

  @spec ensure_repo(String.t()) :: :ok | {:error, term()}
  def ensure_repo(path) do
    if repo_dir?(path) do
      :ok
    else
      {:error, :not_a_repo}
    end
  end

  @spec run(String.t(), keyword()) :: {:ok, map()}
  def run(repo_path, opts \\ []) do
    runs = Keyword.get(opts, :runs, 3)
    scenarios = Keyword.get(opts, :scenarios, build_scenarios())
    tools = Keyword.get(opts, :tools, [:git, :sapling])
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    timer = Keyword.get(opts, :timer, &:timer.tc/1)
    env = Keyword.get(opts, :env, [])

    started_at = DateTime.utc_now()

    results =
      for run_index <- 1..runs,
          scenario <- scenarios,
          tool <- tools,
          command when not is_nil(command) <- [Map.get(scenario.commands, tool)] do
        execute(command, repo_path, env, runner, timer, run_index, scenario.id, tool)
      end

    {:ok,
     %{
       repo_path: repo_path,
       runs: runs,
       tools: tools,
       started_at: started_at,
       results: results
     }}
  end

  @spec summarize([map()]) :: [map()]
  def summarize(results) do
    results
    |> Enum.group_by(fn result -> {result.scenario, result.tool} end)
    |> Enum.map(fn {{scenario, tool}, entries} ->
      durations = Enum.map(entries, & &1.duration_us)
      output_sizes = Enum.map(entries, & &1.output_bytes)
      runs = length(entries)

      %{
        scenario: scenario,
        tool: tool,
        runs: runs,
        avg_us: average(durations),
        min_us: Enum.min(durations),
        max_us: Enum.max(durations),
        avg_output_bytes: average(output_sizes)
      }
    end)
    |> Enum.sort_by(fn entry -> {entry.scenario, entry.tool} end)
  end

  @spec format_markdown(map(), [map()]) :: String.t()
  def format_markdown(report, summary) do
    scenario_map =
      build_scenarios()
      |> Map.new(fn scenario -> {scenario.id, scenario} end)

    command_lines =
      build_scenarios()
      |> Enum.flat_map(fn scenario ->
        Enum.map(scenario.commands, fn {tool, {cmd, args}} ->
          "- #{scenario.description} (#{tool}): `#{cmd} #{Enum.join(args, " ")}`"
        end)
      end)

    tools = Map.get(report, :tools, [])
    tool_versions = Map.get(report, :tool_versions, %{})
    missing_tools = Map.get(report, :missing_tools, [])

    tool_lines =
      cond do
        tools != [] ->
          Enum.map(tools, fn tool ->
            "- #{tool}: #{Map.get(tool_versions, tool, "unknown")}"
          end)

        tool_versions != %{} ->
          Enum.map(tool_versions, fn {tool, version} -> "- #{tool}: #{version}" end)

        true ->
          ["- (not captured)"]
      end

    tools_line =
      case tools do
        [] -> []
        _ -> ["Tools: `#{Enum.join(tools, ", ")}`"]
      end

    missing_lines =
      case missing_tools do
        [] ->
          []

        _ ->
          [
            "",
            "Missing tools: `#{Enum.join(missing_tools, ", ")}`",
            "Results include only available tools."
          ]
      end

    header =
      [
        "# Sapling vs Git benchmark",
        "",
        "This report is generated by `mix micelio.sapling.benchmark`.",
        "",
        "Repo: `#{report.repo_path}`",
        "Runs per scenario: #{report.runs}",
        "Started at: #{DateTime.to_iso8601(report.started_at)}"
      ]
      |> Kernel.++(tools_line)
      |> Kernel.++([
        "",
        "## Tool versions",
        "",
        Enum.join(tool_lines, "\n")
      ])
      |> Kernel.++(missing_lines)
      |> Kernel.++([
        "",
        "## Scenarios",
        "",
        Enum.join(command_lines, "\n"),
        "",
        "## Summary",
        "",
        "| Scenario | Tool | Avg (ms) | Min (ms) | Max (ms) | Runs | Avg output (bytes) |",
        "| --- | --- | --- | --- | --- | --- | --- |"
      ])

    rows =
      Enum.map(summary, fn entry ->
        scenario_label =
          scenario_map
          |> Map.get(entry.scenario)
          |> case do
            nil -> Atom.to_string(entry.scenario)
            scenario -> scenario.description
          end

        "| #{scenario_label} | #{entry.tool} | #{format_ms(entry.avg_us)} | #{format_ms(entry.min_us)} | #{format_ms(entry.max_us)} | #{entry.runs} | #{format_int(entry.avg_output_bytes)} |"
      end)

    (header ++ rows ++ [""])
    |> Enum.join("\n")
  end

  defp execute({cmd, args}, repo_path, env, runner, timer, run_index, scenario, tool) do
    opts =
      case env do
        [] -> [cd: repo_path]
        _ -> [cd: repo_path, env: env]
      end

    {duration_us, {output, status}} = timer.(fn -> runner.(cmd, args, opts) end)

    %{
      tool: tool,
      scenario: scenario,
      run: run_index,
      duration_us: duration_us,
      status: status,
      output_bytes: output |> to_string() |> byte_size()
    }
  end

  defp average([]), do: 0
  defp average(values), do: Enum.sum(values) / length(values)

  defp format_ms(value) do
    value
    |> Kernel./(1000)
    |> Float.round(2)
  end

  defp format_int(value) when is_integer(value), do: value
  defp format_int(value), do: round(value)

  defp normalize_tool(:git), do: :git
  defp normalize_tool(:sapling), do: :sapling
  defp normalize_tool("git"), do: :git
  defp normalize_tool("sapling"), do: :sapling
  defp normalize_tool("sl"), do: :sapling
  defp normalize_tool(_), do: nil

  defp tool_command(:git), do: "git"
  defp tool_command(:sapling), do: "sl"

  defp repo_dir?(path) do
    Enum.any?([".git", ".sl", ".hg"], &File.dir?(Path.join(path, &1)))
  end
end
