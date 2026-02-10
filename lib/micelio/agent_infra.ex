defmodule Micelio.AgentInfra do
  @moduledoc """
  API for shaping agent VM provisioning plans.
  """

  alias Micelio.Accounts.Account
  alias Micelio.AgentInfra.Billing
  alias Micelio.AgentInfra.CloudPlatforms
  alias Micelio.AgentInfra.ProviderRegistry
  alias Micelio.AgentInfra.ProvisioningPlan
  alias Micelio.AgentInfra.ProvisioningRequest
  alias Micelio.AgentInfra.SessionRequest
  alias Micelio.AITokens
  alias Micelio.PromptRequests.PromptRequest

  @doc """
  Builds a provisioning plan from attributes.
  """
  def build_plan(attrs) do
    %ProvisioningPlan{}
    |> ProvisioningPlan.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Builds a provider-ready request from attributes.
  """
  def build_request(attrs) do
    with {:ok, plan} <- build_plan(attrs) do
      {:ok, ProvisioningRequest.from_plan(plan)}
    end
  end

  @doc """
  Builds a provider-ready request after reserving agent quota for the account.
  """
  def build_request_with_quota(%Account{} = account, attrs, opts \\ []) do
    with :ok <- ensure_budget_for_prompt_request(Keyword.get(opts, :prompt_request)),
         {:ok, plan} <- build_plan(attrs),
         {:ok, _event} <- Billing.reserve_for_plan(account, plan, opts) do
      {:ok, ProvisioningRequest.from_plan(plan)}
    end
  end

  @doc """
  Returns a changeset for inspecting or editing a plan.
  """
  def change_plan(%ProvisioningPlan{} = plan, attrs \\ %{}) do
    ProvisioningPlan.changeset(plan, attrs)
  end

  @doc """
  Builds a session request for the Session Manager API.
  """
  def build_session_request(attrs) do
    %SessionRequest{}
    |> SessionRequest.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Returns a changeset for inspecting or editing a session request.
  """
  def change_session_request(%SessionRequest{} = request, attrs \\ %{}) do
    SessionRequest.changeset(request, attrs)
  end

  @doc """
  Returns evaluated cloud platforms for provisioning agent VMs.
  """
  def cloud_platforms do
    CloudPlatforms.all()
  end

  @doc """
  Returns a single platform evaluation by id.
  """
  def cloud_platform(id) do
    CloudPlatforms.find(id)
  end

  @doc """
  Resolves a provisioning provider module by id.
  """
  def provider_module(provider_id, providers \\ ProviderRegistry.providers()) do
    ProviderRegistry.resolve(provider_id, providers)
  end

  defp ensure_budget_for_prompt_request(nil), do: :ok

  defp ensure_budget_for_prompt_request(%PromptRequest{} = prompt_request) do
    AITokens.ensure_budget_for_prompt_request(prompt_request)
  end
end
