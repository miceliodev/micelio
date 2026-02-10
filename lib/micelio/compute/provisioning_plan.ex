defmodule Micelio.AgentInfra.ProvisioningPlan do
  @moduledoc """
  Defines the provisioning plan for agent VMs, including volume mounts.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Micelio.AgentInfra.SandboxProfile
  alias Micelio.AgentInfra.VolumeMount

  @primary_key false
  embedded_schema do
    field :provider, :string
    field :image, :string
    field :cpu_cores, :integer
    field :memory_mb, :integer
    field :disk_gb, :integer
    field :network, :string
    field :ttl_seconds, :integer
    embeds_one :sandbox, SandboxProfile, on_replace: :update
    embeds_many :volumes, VolumeMount, on_replace: :delete
  end

  @type t :: %__MODULE__{
          provider: String.t() | nil,
          image: String.t() | nil,
          cpu_cores: integer() | nil,
          memory_mb: integer() | nil,
          disk_gb: integer() | nil,
          network: String.t() | nil,
          ttl_seconds: integer() | nil,
          sandbox: SandboxProfile.t() | nil,
          volumes: [VolumeMount.t()]
        }

  @doc """
  Builds a changeset for a provisioning plan.
  """
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:provider, :image, :cpu_cores, :memory_mb, :disk_gb, :network, :ttl_seconds])
    |> cast_embed(:sandbox, required: false)
    |> cast_embed(:volumes, required: false)
    |> validate_required([:provider, :image, :cpu_cores, :memory_mb, :disk_gb])
    |> validate_inclusion(:provider, ["firecracker", "cloud_hypervisor", "fly", "aws"])
    |> validate_number(:cpu_cores, greater_than: 0, less_than_or_equal_to: 128)
    |> validate_number(:memory_mb, greater_than: 0)
    |> validate_number(:disk_gb, greater_than: 0)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> validate_length(:image, min: 1, max: 200)
    |> validate_volume_names_unique()
    |> apply_default_sandbox()
    |> validate_volume_access_for_sandbox()
  end

  defp validate_volume_names_unique(changeset) do
    volumes = get_field(changeset, :volumes, [])

    duplicates =
      volumes
      |> Enum.map(& &1.name)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    if duplicates == [] do
      changeset
    else
      add_error(changeset, :volumes, "volume names must be unique")
    end
  end

  defp apply_default_sandbox(changeset) do
    case get_field(changeset, :sandbox) do
      nil -> put_embed(changeset, :sandbox, SandboxProfile.default())
      _sandbox -> changeset
    end
  end

  defp validate_volume_access_for_sandbox(changeset) do
    volumes = get_field(changeset, :volumes, [])

    filesystem_policy =
      case get_field(changeset, :sandbox) do
        %SandboxProfile{filesystem_policy: policy} -> policy
        _ -> "workspace-rw"
      end

    case filesystem_policy do
      "immutable" ->
        if Enum.any?(volumes, &rw_volume?/1) do
          add_error(changeset, :volumes, "must be read-only when filesystem policy is immutable")
        else
          changeset
        end

      "workspace-rw" ->
        invalid_targets =
          volumes
          |> Enum.filter(&rw_volume?/1)
          |> Enum.reject(&workspace_target?/1)

        if invalid_targets == [] do
          changeset
        else
          add_error(
            changeset,
            :volumes,
            "read-write mounts must target /workspace when filesystem policy is workspace-rw"
          )
        end

      _ ->
        changeset
    end
  end

  defp rw_volume?(%VolumeMount{access: "rw"}), do: true
  defp rw_volume?(_volume), do: false

  defp workspace_target?(%VolumeMount{target: target}) when is_binary(target) do
    target == "/workspace" or String.starts_with?(target, "/workspace/")
  end

  defp workspace_target?(_volume), do: false
end
