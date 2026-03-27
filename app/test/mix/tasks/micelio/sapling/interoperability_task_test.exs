defmodule Mix.Tasks.Micelio.Sapling.InteroperabilityTaskTest do
  use ExUnit.Case, async: false

  test "writes an interoperability report to the requested output path" do
    output_path = Path.join(System.tmp_dir!(), "sapling_interop_task_test.md")
    File.rm_rf!(output_path)
    on_exit(fn -> File.rm_rf!(output_path) end)

    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("micelio.sapling.interoperability")

    Mix.Tasks.Micelio.Sapling.Interoperability.run([
      "--tools",
      "git",
      "--output",
      output_path
    ])

    assert File.exists?(output_path)

    content = File.read!(output_path)
    assert String.contains?(content, "Sapling Git interoperability report")
    assert String.contains?(content, "Tools requested: `git`")
  end
end
