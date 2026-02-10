defmodule MicelioWeb.Browser.ProfileHTML do
  use MicelioWeb, :html

  embed_templates("profile_html/*")

  def format_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  def format_date(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.to_date()
    |> Date.to_iso8601()
  end
end
