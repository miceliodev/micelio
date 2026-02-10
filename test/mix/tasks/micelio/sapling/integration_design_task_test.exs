defmodule Mix.Tasks.Micelio.Sapling.IntegrationDesignTaskTest do
  use ExUnit.Case, async: false

  test "writes an integration design report to the requested output path" do
    output_path = Path.join(System.tmp_dir!(), "sapling_integration_design_task_test.md")
    File.rm_rf!(output_path)
    on_exit(fn -> File.rm_rf!(output_path) end)

    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("micelio.sapling.integration_design")

    Mix.Tasks.Micelio.Sapling.IntegrationDesign.run([
      "--output",
      output_path,
      "--started-at",
      "2024-01-01T00:00:00Z"
    ])

    assert File.exists?(output_path)

    content = File.read!(output_path)
    assert String.contains?(content, "Sapling integration layer design")
    assert String.contains?(content, "Started at: 2024-01-01T00:00:00Z")
  end
end
