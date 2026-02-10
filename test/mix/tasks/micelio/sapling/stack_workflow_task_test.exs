defmodule Mix.Tasks.Micelio.Sapling.StackWorkflowTaskTest do
  use ExUnit.Case, async: false

  test "writes a stack workflow report to the requested output path" do
    output_path = Path.join(System.tmp_dir!(), "sapling_stack_workflow_task_test.md")
    File.rm_rf!(output_path)
    on_exit(fn -> File.rm_rf!(output_path) end)

    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("micelio.sapling.stack_workflow")

    Mix.Tasks.Micelio.Sapling.StackWorkflow.run([
      "--sessions",
      "1",
      "--tools",
      "git",
      "--output",
      output_path
    ])

    assert File.exists?(output_path)

    content = File.read!(output_path)
    assert String.contains?(content, "Sapling stacking workflow report")
    assert String.contains?(content, "Tools requested: `git`")
  end
end
