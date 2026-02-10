defmodule MicelioWeb.Badges.ProjectBadge do
  @moduledoc false

  @height 20
  @font_size 11
  @font_family "Verdana,DejaVu Sans,sans-serif"
  @label_color "#2f3237"
  @message_color "#1b7f4b"
  @text_color "#ffffff"
  @padding 10
  @char_width 6

  def render(label, message) when is_binary(label) and is_binary(message) do
    label_text = escape(label)
    message_text = escape(message)
    label_width = text_width(label)
    message_width = text_width(message)
    total_width = label_width + message_width
    message_x = label_width
    label_center = label_width / 2
    message_center = label_width + message_width / 2
    aria_label = escape("#{label}: #{message}")

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total_width}" height="#{@height}" role="img" aria-label="#{aria_label}">
      <title>#{aria_label}</title>
      <rect width="#{label_width}" height="#{@height}" fill="#{@label_color}"/>
      <rect x="#{message_x}" width="#{message_width}" height="#{@height}" fill="#{@message_color}"/>
      <text x="#{label_center}" y="14" fill="#{@text_color}" font-family="#{@font_family}" font-size="#{@font_size}" text-anchor="middle">#{label_text}</text>
      <text x="#{message_center}" y="14" fill="#{@text_color}" font-family="#{@font_family}" font-size="#{@font_size}" text-anchor="middle">#{message_text}</text>
    </svg>
    """
  end

  defp text_width(text) do
    String.length(text) * @char_width + @padding
  end

  defp escape(text) do
    text
    |> Plug.HTML.html_escape()
    |> IO.iodata_to_binary()
  end
end
