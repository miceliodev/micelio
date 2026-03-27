defmodule Micelio.Sapling.StackWorkflowTest do
  use ExUnit.Case, async: true

  alias Micelio.Sapling.StackWorkflow

  test "parse_tools handles defaults and explicit lists" do
    assert {:ok, [:git, :sapling]} = StackWorkflow.parse_tools(nil)
    assert {:ok, [:git]} = StackWorkflow.parse_tools([:git])
    assert {:ok, [:git, :sapling]} = StackWorkflow.parse_tools("git,sapling")
    assert {:error, _} = StackWorkflow.parse_tools("unknown")
  end

  test "tool_availability returns available and missing tools" do
    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    assert %{available: [:git], missing: [:sapling]} ==
             StackWorkflow.tool_availability([:git, :sapling], finder: finder)
  end

  test "run captures stack workflow steps with injected runner" do
    runner = fn cmd, args, opts ->
      send(self(), {:cmd, cmd, args, opts})
      {"ok", 0}
    end

    tmp_root = Path.join(System.tmp_dir!(), "stack_workflow_test")
    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)

    {:ok, report} =
      StackWorkflow.run(
        sessions: 2,
        tools: [:git],
        runner: runner,
        tmp_root: tmp_root,
        cleanup: false
      )

    assert report.sessions == 2
    assert report.available_tools == [:git]
    assert length(report.results) == 1
    assert Enum.any?(hd(report.results).steps, &(&1.label == :stack_view))

    assert_received {:cmd, "git",
                     ["log", "--graph", "--oneline", "--decorate", "--all", "-n", "20"], _opts}
  end

  test "run captures sapling stack view without git branch steps" do
    runner = fn cmd, args, opts ->
      send(self(), {:cmd, cmd, args, opts})
      {"ok", 0}
    end

    finder = fn
      "sl" -> "/usr/bin/sl"
      _ -> nil
    end

    tmp_root = Path.join(System.tmp_dir!(), "stack_workflow_sapling_test")
    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)

    {:ok, report} =
      StackWorkflow.run(
        sessions: 1,
        tools: [:sapling],
        runner: runner,
        tmp_root: tmp_root,
        cleanup: false,
        finder: finder
      )

    assert report.available_tools == [:sapling]
    assert Enum.any?(hd(report.results).steps, &(&1.label == :stack_view))
    refute Enum.any?(hd(report.results).steps, &(&1.label == :checkout_branch))
    assert_received {:cmd, "sl", ["stack"], _opts}
    assert_received {:cmd, "sl", ["log", "-l", "20"], _opts}
  end

  test "format_markdown renders report sections" do
    report = %{
      tools: [:git],
      available_tools: [:git],
      missing_tools: [:sapling],
      sessions: 3,
      started_at: ~U[2024-01-01 00:00:00Z],
      results: [
        %{
          tool: :git,
          repo_path: "/tmp/repo",
          status: :ok,
          steps: [
            %{
              label: :stack_view,
              command: "git",
              args: ["log"],
              status: 0,
              output: "graph"
            }
          ]
        }
      ]
    }

    markdown = StackWorkflow.format_markdown(report)

    assert String.contains?(markdown, "Sapling stacking workflow report")
    assert String.contains?(markdown, "mix micelio.sapling.stack_workflow")
    assert String.contains?(markdown, "Sessions simulated: 3")
    assert String.contains?(markdown, "Missing tools: `sapling`")
    assert String.contains?(markdown, "### git")
    assert String.contains?(markdown, "stack_view")
  end
end
