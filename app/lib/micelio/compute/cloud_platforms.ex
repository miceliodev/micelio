defmodule Micelio.AgentInfra.CloudPlatforms do
  @moduledoc """
  Curated evaluation of cloud platforms for provisioning agent VMs.
  """

  @type platform :: %{
          id: atom(),
          name: String.t(),
          summary: String.t(),
          strengths: [String.t()],
          risks: [String.t()],
          suitability: [String.t()],
          notes: [String.t()]
        }

  @platforms [
    %{
      id: :aws,
      name: "AWS",
      summary:
        "Best overall coverage and Firecracker alignment via Nitro; higher operational and cost complexity.",
      strengths: [
        "Native Firecracker lineage via Nitro and strong VPC controls",
        "Broadest region footprint for latency and compliance",
        "Spot and Savings Plans help long-running VM costs",
        "Mature IAM and audit tooling for multi-tenant isolation"
      ],
      risks: [
        "Cost management complexity without tight guardrails",
        "Higher setup overhead for IAM, networking, and quotas",
        "Per-region limits can slow rapid scale-outs"
      ],
      suitability: [
        "Primary platform for global scale or regulated deployments",
        "Best fit when Firecracker parity is a priority"
      ],
      notes: [
        "Prefer Nitro-based families for microVM performance",
        "Budget alarms and quota automation are mandatory"
      ]
    },
    %{
      id: :gcp,
      name: "GCP",
      summary: "Strong network and pricing flexibility, but lacks native Firecracker support.",
      strengths: [
        "Custom machine types and preemptible options",
        "Clean networking and repository isolation model",
        "Good fit for data-heavy workloads adjacent to GCP services"
      ],
      risks: [
        "No native Firecracker; requires cloud-hypervisor or KVM tuning",
        "Region coverage is smaller than AWS for latency-sensitive footprints"
      ],
      suitability: [
        "Secondary platform for multi-cloud resilience",
        "Good for analytics-heavy workflows in GCP ecosystems"
      ],
      notes: [
        "Validate nested virtualization constraints per region",
        "Plan for image parity with Firecracker-based providers"
      ]
    },
    %{
      id: :hetzner,
      name: "Hetzner",
      summary:
        "Cost-effective with bare metal options, but limited regions and enterprise features.",
      strengths: [
        "Very competitive pricing for steady-state VM fleets",
        "Bare metal availability for dedicated performance",
        "Simple API and predictable billing"
      ],
      risks: [
        "Limited region footprint for global latency targets",
        "Smaller ecosystem for managed security tooling",
        "Fewer managed services for adjacent workloads"
      ],
      suitability: [
        "Cost-optimized steady-state workloads in Europe",
        "Great for baseline capacity with burst elsewhere"
      ],
      notes: [
        "Use for warm pools and non-compliance-critical workloads",
        "Plan for backup provider in other geos"
      ]
    },
    %{
      id: :fly,
      name: "Fly.io",
      summary: "Managed Firecracker microVMs with fast startup and global edge reach.",
      strengths: [
        "Firecracker-based VMs with straightforward developer UX",
        "Global footprint for low-latency agent sessions",
        "Integrated networking and volume primitives"
      ],
      risks: [
        "Higher unit cost for sustained heavy workloads",
        "Less control over underlying host configuration",
        "Smaller ecosystem for enterprise compliance controls"
      ],
      suitability: [
        "Burst capacity and rapid spin-up agent sessions",
        "Global edge deployments without owning infra"
      ],
      notes: [
        "Monitor cost for long-running jobs",
        "Use for overflow or fast-turnaround workloads"
      ]
    }
  ]

  @doc "Returns the full evaluation list."
  @spec all() :: [platform()]
  def all do
    @platforms
  end

  @doc "Finds a platform by id."
  @spec find(atom() | String.t()) :: platform() | nil
  def find(id) when is_atom(id) do
    Enum.find(@platforms, fn platform -> platform.id == id end)
  end

  def find(id) when is_binary(id) do
    id
    |> String.downcase()
    |> String.to_existing_atom()
    |> find()
  rescue
    ArgumentError -> nil
  end

  @doc "Returns recommended primary and secondary providers."
  @spec recommendations() :: %{primary: atom(), secondary: atom(), overflow: atom()}
  def recommendations do
    %{primary: :aws, secondary: :gcp, overflow: :fly}
  end
end
