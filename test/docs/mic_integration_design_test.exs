defmodule Micelio.Docs.MicIntegrationDesignTest do
  use ExUnit.Case, async: true

  test "mic integration design doc has required sections" do
    path = Path.expand("../../docs/compute/mic-integration-design.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(contents, "# mic Integration Design")
    assert String.contains?(contents, "## Goals")
    assert String.contains?(contents, "## Architecture Overview")
    assert String.contains?(contents, "## Session Lifecycle")
    assert String.contains?(contents, "## Workspace Mapping")
    assert String.contains?(contents, "## Security and Authentication")
    assert String.contains?(contents, "## Open Questions")
  end
end
