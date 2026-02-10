defmodule Micelio.Ops.PackerFirecrackerPocTest do
  use ExUnit.Case, async: true

  test "packer firecracker PoC assets exist" do
    readme = Path.expand("../../ops/packer-firecracker/README.md", __DIR__)
    template = Path.expand("../../ops/packer-firecracker/firecracker.pkr.hcl", __DIR__)
    user_data = Path.expand("../../ops/packer-firecracker/http/user-data", __DIR__)
    meta_data = Path.expand("../../ops/packer-firecracker/http/meta-data", __DIR__)
    script = Path.expand("../../ops/packer-firecracker/scripts/bootstrap.sh", __DIR__)

    assert File.exists?(readme)
    assert File.exists?(template)
    assert File.exists?(user_data)
    assert File.exists?(meta_data)
    assert File.exists?(script)

    contents = File.read!(readme)

    assert String.contains?(contents, "# Packer Firecracker Image Builder (PoC)")
    assert String.contains?(contents, "## Prerequisites")
    assert String.contains?(contents, "## Build")
    assert String.contains?(contents, "## Validation Checklist")
  end
end
