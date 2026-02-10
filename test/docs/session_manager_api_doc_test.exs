defmodule Micelio.Docs.SessionManagerApiDocTest do
  use ExUnit.Case, async: true

  test "session manager API compute doc covers the contract" do
    doc = Path.expand("../../docs/compute/session-manager-api.md", __DIR__)

    assert File.exists?(doc)

    contents = File.read!(doc)

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
