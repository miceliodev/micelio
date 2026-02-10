defmodule Micelio.Sapling.AgentCommitWorkflowTest do
  use ExUnit.Case, async: true

  alias Micelio.Sapling.AgentCommitWorkflow

  test "parse_tools handles defaults and explicit lists" do
    assert {:ok, [:git, :sapling]} = AgentCommitWorkflow.parse_tools(nil)
    assert {:ok, [:git]} = AgentCommitWorkflow.parse_tools([:git])
    assert {:ok, [:git, :sapling]} = AgentCommitWorkflow.parse_tools("git,sapling")
    assert {:error, _} = AgentCommitWorkflow.parse_tools("unknown")
  end

  test "tool_availability returns available and missing tools" do
    finder = fn
      "git" -> "/usr/bin/git"
      "sl" -> nil
    end

    assert %{available: [:git], missing: [:sapling]} ==
             AgentCommitWorkflow.tool_availability([:git, :sapling], finder: finder)
  end

  test "run captures commit messages with Mic-Session trailers" do
    runner = fn cmd, args, opts ->
      send(self(), {:cmd, cmd, args, opts})
      {"ok", 0}
    end

    tmp_root = Path.join(System.tmp_dir!(), "agent_commit_workflow_test")
    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)

    {:ok, report} =
      AgentCommitWorkflow.run(
        sessions: 2,
        tools: [:git],
        runner: runner,
        tmp_root: tmp_root,
        cleanup: false
      )

    assert report.sessions == 2
    assert report.available_tools == [:git]
    assert length(report.results) == 1

    steps = hd(report.results).steps

    assert Enum.any?(steps, fn step ->
             step.label == :commit_session and
               String.contains?(Enum.at(step.args, 2), "Mic-Session: session-1")
           end)

    assert_received {:cmd, "git",
                     ["log", "--graph", "--oneline", "--decorate", "--all", "-n", "10"], _opts}
  end

  test "format_markdown renders report sections" do
    report = %{
      tools: [:git],
      available_tools: [:git],
      missing_tools: [:sapling],
      sessions: 3,
      session_ids: ["session-1"],
      started_at: ~U[2024-01-01 00:00:00Z],
      results: [
        %{
          tool: :git,
          repo_path: "/tmp/repo",
          status: :ok,
          steps: [
            %{
              label: :message_view,
              command: "git",
              args: ["log"],
              status: 0,
              output: "messages"
            }
          ]
        }
      ]
    }

    markdown = AgentCommitWorkflow.format_markdown(report)

    assert String.contains?(markdown, "Sapling agent commit workflow report")
    assert String.contains?(markdown, "mix micelio.sapling.agent_commit_workflow")
    assert String.contains?(markdown, "Sessions simulated: 3")
    assert String.contains?(markdown, "Missing tools: `sapling`")
    assert String.contains?(markdown, "Session IDs: `session-1`")
    assert String.contains?(markdown, "### git")
    assert String.contains?(markdown, "message_view")
  end
end
