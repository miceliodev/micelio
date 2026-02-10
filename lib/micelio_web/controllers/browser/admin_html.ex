defmodule MicelioWeb.Browser.AdminHTML do
  @moduledoc """
  HTML templates for the admin dashboard.
  """

  use MicelioWeb, :html

  embed_templates "admin_html/*"

  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  def format_acceptance_rate(accepted, total) when is_integer(accepted) and is_integer(total) do
    if total > 0 do
      rate = accepted / total * 100
      "#{:erlang.float_to_binary(rate, decimals: 1)}%"
    else
      "n/a"
    end
  end
end
