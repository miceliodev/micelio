defmodule Mix.Tasks.Micelio.Sapling.AgentCommitWorkflowTaskTest do
  use ExUnit.Case, async: false

  test "writes an agent commit workflow report to the requested output path" do
    output_path = Path.join(System.tmp_dir!(), "sapling_agent_commit_workflow_task_test.md")
    File.rm_rf!(output_path)
    on_exit(fn -> File.rm_rf!(output_path) end)

    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("micelio.sapling.agent_commit_workflow")

    Mix.Tasks.Micelio.Sapling.AgentCommitWorkflow.run([
      "--sessions",
      "1",
      "--tools",
      "git",
      "--output",
      output_path
    ])

    assert File.exists?(output_path)

    content = File.read!(output_path)
    assert String.contains?(content, "Sapling agent commit workflow report")
    assert String.contains?(content, "Tools requested: `git`")
  end
end
