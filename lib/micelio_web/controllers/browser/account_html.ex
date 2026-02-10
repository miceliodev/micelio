defmodule MicelioWeb.Browser.AccountHTML do
  use MicelioWeb, :html

  embed_templates "account_html/*"

  def activity_action_label(:session_landed), do: "Landed a session in"
  def activity_action_label(:prompt_request_submitted), do: "Submitted prompt request in"
  def activity_action_label(:repository_starred), do: "Starred"
  def activity_action_label(:repository_created), do: "Created repository"
  def activity_action_label(_), do: "Updated"

  def prompt_request_origin_label(origin),
    do: Micelio.PromptRequests.PromptRequest.origin_label(origin)

  def prompt_request_origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  def prompt_request_origin_value(origin) when is_binary(origin), do: origin
  def prompt_request_origin_value(_), do: "unknown"
end
