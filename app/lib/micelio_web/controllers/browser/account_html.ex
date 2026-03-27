defmodule MicelioWeb.Browser.AccountHTML do
  use MicelioWeb, :html

  embed_templates "account_html/*"

  def activity_action_label(:session_landed), do: "Landed a session in"
  def activity_action_label(:plan_submitted), do: "Submitted plan in"
  def activity_action_label(:repository_created), do: "Created repository"
  def activity_action_label(_), do: "Updated"

  def plan_origin_label(origin), do: Micelio.Plans.Plan.origin_label(origin)

  def plan_origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  def plan_origin_value(origin) when is_binary(origin), do: origin
  def plan_origin_value(_), do: "unknown"

  def account_display_name(account) do
    account.handle
  end

  def account_reference_label(account) do
    "@#{account.handle}"
  end

  def repository_reference_label(repository) do
    "#{repository.organization.account.handle}/#{repository.handle}"
  end
end
