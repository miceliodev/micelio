defmodule Micelio.Sapling.IntegrationDesignTest do
  use ExUnit.Case, async: true

  alias Micelio.Sapling.IntegrationDesign

  test "build_report uses defaults and overrides started_at" do
    started_at = ~U[2024-01-02 03:04:05Z]
    report = IntegrationDesign.build_report(started_at: started_at)

    assert report.started_at == started_at
    assert String.contains?(Enum.join(report.goals, " "), "Git interoperability")
    assert String.contains?(Enum.join(report.assumptions, " "), "Sapling")
  end

  test "format_markdown renders key sections" do
    report = IntegrationDesign.build_report(started_at: ~U[2024-01-01 00:00:00Z])
    markdown = IntegrationDesign.format_markdown(report)

    assert String.contains?(markdown, "Sapling integration layer design")
    assert String.contains?(markdown, "## Goals")
    assert String.contains?(markdown, "## Adapter contract")
    assert String.contains?(markdown, "## Data model")
    assert String.contains?(markdown, "projects.vcs_backend")
    assert String.contains?(markdown, "## Rollout plan")
    assert String.contains?(markdown, "Started at: 2024-01-01T00:00:00Z")
  end

  test "format_markdown renders bullet lists for open questions" do
    report = IntegrationDesign.build_report(started_at: ~U[2024-01-01 00:00:00Z])
    markdown = IntegrationDesign.format_markdown(report)

    assert String.contains?(markdown, "## Open questions")

    assert String.contains?(
             markdown,
             "- Should Sapling be required only for new repositories or also allow migrations?"
           )

    assert String.contains?(
             markdown,
             "- Which Sapling stack view should power the web UI (stack vs log)?"
           )
  end
end
