defmodule MicelioWeb.DocsI18n do
  @moduledoc false

  def translate_categories(categories) when is_map(categories) do
    Map.new(categories, fn {category_id, category_info} ->
      {category_id, translate_category_info(category_info)}
    end)
  end

  def translate_category_info(nil), do: nil

  def translate_category_info(%{title: title, description: description} = category_info) do
    %{
      category_info
      | title: Gettext.gettext(MicelioWeb.Gettext, title),
        description: Gettext.gettext(MicelioWeb.Gettext, description)
    }
  end
end
