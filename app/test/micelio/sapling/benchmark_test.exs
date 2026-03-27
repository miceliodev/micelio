defmodule Micelio.Sapling.BenchmarkTest do
  use ExUnit.Case, async: true

  alias Micelio.Sapling.Benchmark

  test "parse_tools handles defaults and explicit lists" do
    assert {:ok, [:git, :sapling]} = Benchmark.parse_tools(nil)
    assert {:ok, [:git]} = Benchmark.parse_tools([:git])
    assert {:ok, [:git, :sapling]} = Benchmark.parse_tools("git,sapling")
    assert {:error, _} = Benchmark.parse_tools("unknown")
  end

  test "ensure_tools reports missing executables" do
    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    assert :ok == Benchmark.ensure_tools([:git], finder: finder)

    assert {:error, {:missing_tools, [:sapling]}} =
             Benchmark.ensure_tools([:git, :sapling], finder: finder)
  end

  test "tool_availability returns available and missing tools" do
    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    assert %{available: [:git], missing: [:sapling]} ==
             Benchmark.tool_availability([:git, :sapling], finder: finder)
  end

  test "tool_versions captures version output" do
    runner = fn
      "git", ["--version"], _opts -> {"git version 2.44.0\n", 0}
      "sl", ["--version"], _opts -> {"sapling version 0.1.0\n", 0}
    end

    assert %{git: "git version 2.44.0", sapling: "sapling version 0.1.0"} ==
             Benchmark.tool_versions([:git, :sapling], runner: runner)
  end

  test "ensure_repo verifies repository markers" do
    tmp_dir = Path.join(System.tmp_dir!(), "sapling_repo_test")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, ".git"))
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert :ok == Benchmark.ensure_repo(tmp_dir)
    assert {:error, :not_a_repo} = Benchmark.ensure_repo(System.tmp_dir!())
  end

  test "run executes scenarios with injected runner" do
    scenarios = [
      %{
        id: :status,
        description: "status",
        commands: %{git: {"git", ["status"]}, sapling: {"sl", ["status"]}}
      }
    ]

    runner = fn cmd, args, opts ->
      send(self(), {:cmd, cmd, args, opts})
      {"ok", 0}
    end

    timer = fn fun -> {1234, fun.()} end

    {:ok, report} =
      Benchmark.run("/repo",
        runs: 2,
        scenarios: scenarios,
        tools: [:git],
        runner: runner,
        timer: timer
      )

    assert report.runs == 2
    assert length(report.results) == 2
    assert Enum.all?(report.results, &(&1.tool == :git))

    assert_received {:cmd, "git", ["status"], opts}
    assert Keyword.get(opts, :cd) == "/repo"
  end

  test "format_markdown renders a summary table" do
    report = %{
      repo_path: "/repo",
      runs: 1,
      started_at: ~U[2024-01-01 00:00:00Z],
      tools: [:git],
      tool_versions: %{git: "git version 2.44.0"},
      missing_tools: [:sapling]
    }

    summary = [
      %{
        scenario: :status,
        tool: :git,
        runs: 1,
        avg_us: 1000,
        min_us: 900,
        max_us: 1100,
        avg_output_bytes: 42
      }
    ]

    markdown = Benchmark.format_markdown(report, summary)

    assert String.contains?(markdown, "Sapling vs Git benchmark")
    assert String.contains?(markdown, "mix micelio.sapling.benchmark")
    assert String.contains?(markdown, "Tool versions")
    assert String.contains?(markdown, "git version 2.44.0")
    assert String.contains?(markdown, "Missing tools: `sapling`")
    assert String.contains?(markdown, "Working tree status")
    assert String.contains?(markdown, "| Working tree status | git")
  end
end
