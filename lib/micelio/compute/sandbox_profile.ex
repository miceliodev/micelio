defmodule Micelio.AgentInfra.SandboxProfile do
  @moduledoc """
  Defines the sandbox policies applied to agent execution environments.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :isolation, :string, default: "microvm"
    field :network_policy, :string, default: "egress-only"
    field :filesystem_policy, :string, default: "workspace-rw"
    field :run_as_user, :string, default: "agent"
    field :seccomp_profile, :string, default: "default"
    field :capabilities, {:array, :string}, default: []
    field :allowlist_hosts, {:array, :string}, default: []
    field :max_processes, :integer, default: 256
    field :max_open_files, :integer, default: 1024
  end

  @type t :: %__MODULE__{
          isolation: String.t() | nil,
          network_policy: String.t() | nil,
          filesystem_policy: String.t() | nil,
          run_as_user: String.t() | nil,
          seccomp_profile: String.t() | nil,
          capabilities: [String.t()],
          allowlist_hosts: [String.t()],
          max_processes: integer() | nil,
          max_open_files: integer() | nil
        }

  @doc """
  Returns the default sandbox profile.
  """
  def default do
    %__MODULE__{}
  end

  @doc """
  Builds a changeset for a sandbox profile.
  """
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :isolation,
      :network_policy,
      :filesystem_policy,
      :run_as_user,
      :seccomp_profile,
      :capabilities,
      :allowlist_hosts,
      :max_processes,
      :max_open_files
    ])
    |> validate_required([:isolation, :network_policy, :filesystem_policy, :run_as_user])
    |> validate_inclusion(:isolation, ["microvm", "container", "process"])
    |> validate_inclusion(:network_policy, ["none", "egress-only", "restricted", "full"])
    |> validate_inclusion(:filesystem_policy, ["immutable", "workspace-rw", "full-rw"])
    |> validate_length(:run_as_user, min: 1, max: 64)
    |> validate_run_as_user()
    |> validate_length(:seccomp_profile, min: 1, max: 64)
    |> validate_number(:max_processes, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_number(:max_open_files, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_capabilities()
    |> validate_allowlist_hosts()
    |> validate_allowlist_requirement()
  end

  def to_request(%__MODULE__{} = profile) do
    %{
      isolation: profile.isolation,
      network_policy: profile.network_policy,
      filesystem_policy: profile.filesystem_policy,
      run_as_user: profile.run_as_user,
      seccomp_profile: profile.seccomp_profile,
      capabilities: profile.capabilities,
      allowlist_hosts: profile.allowlist_hosts,
      max_processes: profile.max_processes,
      max_open_files: profile.max_open_files
    }
  end

  defp validate_run_as_user(changeset) do
    validate_change(changeset, :run_as_user, fn :run_as_user, user ->
      if String.downcase(user) == "root" do
        [run_as_user: "must be non-root for sandboxed execution"]
      else
        []
      end
    end)
  end

  defp validate_capabilities(changeset) do
    validate_change(changeset, :capabilities, fn :capabilities, caps ->
      invalid =
        caps
        |> Enum.reject(&valid_capability?/1)

      if invalid == [] do
        []
      else
        [capabilities: "must contain only lowercase capability names"]
      end
    end)
  end

  defp valid_capability?(capability) do
    String.match?(capability, ~r/^[a-z][a-z0-9_]*$/)
  end

  defp validate_allowlist_hosts(changeset) do
    validate_change(changeset, :allowlist_hosts, fn :allowlist_hosts, hosts ->
      invalid =
        hosts
        |> Enum.reject(&valid_host?/1)

      if invalid == [] do
        []
      else
        [allowlist_hosts: "must be hostnames or CIDR blocks"]
      end
    end)
  end

  defp valid_host?(host) do
    hostname? = String.match?(host, ~r/^[a-z0-9][a-z0-9.-]{0,251}[a-z0-9]$/i)
    cidr? = String.match?(host, ~r/^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/)
    hostname? or cidr?
  end

  defp validate_allowlist_requirement(changeset) do
    policy = get_field(changeset, :network_policy, "egress-only")
    allowlist = get_field(changeset, :allowlist_hosts, [])

    cond do
      policy == "restricted" and allowlist == [] ->
        add_error(changeset, :allowlist_hosts, "must be provided for restricted network policy")

      policy == "none" and allowlist != [] ->
        add_error(changeset, :allowlist_hosts, "must be empty when network policy is none")

      true ->
        changeset
    end
  end
end
