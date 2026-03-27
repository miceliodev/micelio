defmodule MicelioWeb.Browser.ChangelogHTML do
  use MicelioWeb, :html

  embed_templates "changelog_html/*"

  @doc """
  Formats a date for display.
  """
  def format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
