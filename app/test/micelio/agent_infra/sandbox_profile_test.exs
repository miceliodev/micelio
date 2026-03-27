defmodule Micelio.AgentInfra.SandboxProfileTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra.SandboxProfile

  test "changeset/2 requires allowlist hosts when network is restricted" do
    changeset =
      SandboxProfile.changeset(%SandboxProfile{}, %{
        network_policy: "restricted"
      })

    assert "must be provided for restricted network policy" in errors_on(changeset).allowlist_hosts
  end

  test "changeset/2 rejects root user" do
    changeset =
      SandboxProfile.changeset(%SandboxProfile{}, %{
        run_as_user: "root"
      })

    assert "must be non-root for sandboxed execution" in errors_on(changeset).run_as_user
  end

  test "changeset/2 validates allowlist host formats" do
    changeset =
      SandboxProfile.changeset(%SandboxProfile{}, %{
        network_policy: "restricted",
        allowlist_hosts: ["bad host", "10.0.0.0/33"]
      })

    assert "must be hostnames or CIDR blocks" in errors_on(changeset).allowlist_hosts
  end

  test "changeset/2 rejects allowlist hosts when network is none" do
    changeset =
      SandboxProfile.changeset(%SandboxProfile{}, %{
        network_policy: "none",
        allowlist_hosts: ["example.com"]
      })

    assert "must be empty when network policy is none" in errors_on(changeset).allowlist_hosts
  end

  test "changeset/2 rejects invalid capability names" do
    changeset =
      SandboxProfile.changeset(%SandboxProfile{}, %{
        capabilities: ["CAP_SYS_ADMIN", "net_admin"]
      })

    assert "must contain only lowercase capability names" in errors_on(changeset).capabilities
  end
end
