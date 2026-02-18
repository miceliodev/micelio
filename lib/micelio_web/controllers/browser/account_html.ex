defmodule MicelioWeb.Browser.AccountHTML do
  use MicelioWeb, :html

  embed_templates "account_html/*"

  def activity_action_label(:session_landed), do: "Landed a session in"
  def activity_action_label(:plan_submitted), do: "Submitted plan in"
  def activity_action_label(:repository_starred), do: "Starred"
  def activity_action_label(:repository_created), do: "Created repository"
  def activity_action_label(_), do: "Updated"

  def plan_origin_label(origin), do: Micelio.Plans.Plan.origin_label(origin)

  def plan_origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  def plan_origin_value(origin) when is_binary(origin), do: origin
  def plan_origin_value(_), do: "unknown"

  def account_display_name(account, organization, forge_namespace) do
    cond do
      is_map(forge_namespace) and is_binary(forge_namespace.owner) and forge_namespace.owner != "" ->
        forge_namespace.owner

      organization && is_binary(organization.name) && String.trim(organization.name) != "" ->
        organization.name

      true ->
        account.handle
    end
  end

  def account_reference_label(account, forge_namespace) do
    if is_map(forge_namespace) and is_binary(forge_namespace.host) and
         is_binary(forge_namespace.owner) and forge_namespace.host != "" and
         forge_namespace.owner != "" do
      "#{forge_namespace.host}/#{forge_namespace.owner}"
    else
      "@#{account.handle}"
    end
  end

  def repository_reference_label(repository) do
    host = normalize_forge_value(repository.forge_host)
    owner = normalize_forge_value(repository.forge_owner)
    repo = normalize_forge_value(repository.forge_repo) || repository.handle

    if host && owner && repo do
      "#{host}/#{owner}/#{repo}"
    else
      "#{repository.organization.account.handle}/#{repository.handle}"
    end
  end

  def github_forge?(forge_namespace) do
    is_map(forge_namespace) and forge_namespace.provider == "github"
  end

  defp normalize_forge_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_forge_value(_), do: nil
end
