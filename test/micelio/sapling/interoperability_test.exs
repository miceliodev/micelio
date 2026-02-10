defmodule Micelio.Sapling.InteroperabilityTest do
  use ExUnit.Case, async: true

  alias Micelio.Sapling.Interoperability

  test "parse_tools handles defaults and explicit lists" do
    assert {:ok, [:git, :sapling]} = Interoperability.parse_tools(nil)
    assert {:ok, [:git]} = Interoperability.parse_tools([:git])
    assert {:ok, [:git, :sapling]} = Interoperability.parse_tools("git,sapling")
    assert {:error, _} = Interoperability.parse_tools("unknown")
  end

  test "tool_availability returns available and missing tools" do
    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    assert %{available: [:git], missing: [:sapling]} ==
             Interoperability.tool_availability([:git, :sapling], finder: finder)
  end

  test "tool_versions captures version output" do
    runner = fn
      "git", ["--version"], _opts -> {"git version 2.44.0\n", 0}
      "sl", ["--version"], _opts -> {"sapling version 0.1.0\n", 0}
    end

    assert %{git: "git version 2.44.0", sapling: "sapling version 0.1.0"} ==
             Interoperability.tool_versions([:git, :sapling], runner: runner)
  end

  test "run records interoperability steps with injected runner" do
    tmp_root = Path.join(System.tmp_dir!(), "sapling_interop_test")
    File.rm_rf!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)

    runner = fn cmd, args, opts ->
      send(self(), {:cmd, cmd, args, opts})
      {"ok", 0}
    end

    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    {:ok, report} =
      Interoperability.run(
        tools: [:git, :sapling],
        runner: runner,
        finder: finder,
        tmp_root: tmp_root
      )

    assert length(report.results) == 2
    assert %{git: "ok"} = report.tool_versions
    assert Enum.all?(report.results, &(&1.compatibility == :blocked))

    assert_received {:cmd, "git", ["init"], opts}
    assert Keyword.get(opts, :cd) =~ "sapling_interop_git_"
  end

  test "run marks compatibility ok when both tools are available" do
    tmp_root = Path.join(System.tmp_dir!(), "sapling_interop_ok_test")
    File.rm_rf!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)

    runner = fn _cmd, _args, _opts -> {"ok", 0} end

    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> "/usr/bin/sl"
    end

    {:ok, report} =
      Interoperability.run(
        tools: [:git, :sapling],
        runner: runner,
        finder: finder,
        tmp_root: tmp_root
      )

    assert Enum.all?(report.results, &(&1.status == :ok))
    assert Enum.all?(report.results, &(&1.compatibility == :ok))
  end

  test "format_markdown renders scenario details" do
    report = %{
      tools: [:git, :sapling],
      available_tools: [:git],
      missing_tools: [:sapling],
      tool_versions: %{git: "git version 2.44.0"},
      started_at: ~U[2024-01-01 00:00:00Z],
      results: [
        %{
          description: "Git repo opened with Sapling",
          repo_path: "/tmp/git",
          status: :ok,
          steps: [
            %{label: :git_init, command: "git", args: ["init"], status: 0, output: "ok"},
            %{
              label: :git_status,
              command: "git",
              args: ["status", "--short"],
              status: 0,
              output: "ok"
            },
            %{
              label: :git_log,
              command: "git",
              args: ["log", "-n", "5", "--oneline"],
              status: 0,
              output: "ok"
            }
          ]
        }
      ]
    }

    markdown = Interoperability.format_markdown(report)

    assert String.contains?(markdown, "Sapling Git interoperability report")
    assert String.contains?(markdown, "mix micelio.sapling.interoperability")
    assert String.contains?(markdown, "Missing tools: `sapling`")
    assert String.contains?(markdown, "## Summary")
    assert String.contains?(markdown, "Git repo opened with Sapling: ok (status ok)")
    assert String.contains?(markdown, "Git repo opened with Sapling")
    assert String.contains?(markdown, "git version 2.44.0")
    assert String.contains?(markdown, "Compatibility: ok")
  end
end
