defmodule Micelio.Ops.NomadFirecrackerPrototypeTest do
  use ExUnit.Case, async: true

  test "prototype docs and artifacts exist" do
    readme = Path.expand("../../ops/nomad-firecracker/README.md", __DIR__)
    job_spec = Path.expand("../../ops/nomad-firecracker/nomad-firecracker-agent.hcl", __DIR__)

    firecracker_config =
      Path.expand("../../ops/nomad-firecracker/firecracker-micelio.json", __DIR__)

    assert File.exists?(readme)
    assert File.exists?(job_spec)
    assert File.exists?(firecracker_config)

    contents = File.read!(readme)

    assert String.contains?(contents, "# Nomad + Firecracker Prototype")
    assert String.contains?(contents, "## Hardware")
    assert String.contains?(contents, "## Nomad Host Setup")
    assert String.contains?(contents, "## Firecracker Artifacts")
    assert String.contains?(contents, "## Validation Steps")
    assert String.contains?(contents, "## Results")
  end
end
