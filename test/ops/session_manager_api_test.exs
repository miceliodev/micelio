defmodule Micelio.Ops.SessionManagerApiTest do
  use ExUnit.Case, async: true

  test "session manager API design doc exists" do
    readme = Path.expand("../../ops/session-manager-api/README.md", __DIR__)

    assert File.exists?(readme)

    contents = File.read!(readme)

    assert String.contains?(contents, "# Session Manager API")
    assert String.contains?(contents, "## Overview")
    assert String.contains?(contents, "## Transport and Versioning")
    assert String.contains?(contents, "## Authentication")
    assert String.contains?(contents, "## Endpoints")
    assert String.contains?(contents, "## Session Schema")
    assert String.contains?(contents, "## Session Request Schema")
    assert String.contains?(contents, "## Provisioning Plan Schema")
    assert String.contains?(contents, "## Sandbox Profile Schema")
    assert String.contains?(contents, "## Volume Mount Schema")
    assert String.contains?(contents, "## State Transitions")
    assert String.contains?(contents, "## Errors")
    assert String.contains?(contents, "## Idempotency")
    assert String.contains?(contents, "## Observability")
  end
end
