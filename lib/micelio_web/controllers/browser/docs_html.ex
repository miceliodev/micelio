defmodule MicelioWeb.Browser.DocsHTML do
  @moduledoc """
  This module contains pages rendered by DocsController.
  """

  use MicelioWeb, :html

  embed_templates "docs_html/*"

  def category_title(category_id, categories) do
    case Map.get(categories, category_id) do
      %{title: title} -> title
      _ -> category_id
    end
  end

  @doc """
  Humanizes a snake_case key into a readable title.
  """
  def humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
