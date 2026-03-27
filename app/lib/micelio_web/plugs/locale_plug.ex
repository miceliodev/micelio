defmodule MicelioWeb.LocalePlug do
  @moduledoc """
  Plug for handling locale detection and setting.

  Marketing pages use URL-based locale detection only:
  - /ja/about → Japanese
  - /ko/ → Korean
  - / or /about → English (default)

  Session and Accept-Language headers are not used for locale detection.
  """

  use Gettext, backend: MicelioWeb.Gettext

  import Plug.Conn

  @default_locale "en"
  @supported_locales ~w(en ko zh_CN zh_TW ja)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = detect_locale(conn)
    Gettext.put_locale(MicelioWeb.Gettext, locale)

    current_path = current_path_without_locale(conn)

    conn
    |> assign(:locale, locale)
    |> assign(:current_path, current_path)
  end

  defp current_path_without_locale(conn) do
    path = conn.request_path

    case String.split(path, "/", parts: 3) do
      ["", locale | rest] when locale in @supported_locales and locale != "en" ->
        case rest do
          [] -> "/"
          [""] -> "/"
          [remaining] -> "/" <> remaining
        end

      _ ->
        path
    end
  end

  @doc """
  Detects locale from URL path prefix.

  Returns the locale if the first path segment is a supported locale,
  otherwise returns the default locale (English).
  """
  def detect_locale(conn) do
    locale_from_path(conn) || @default_locale
  end

  defp locale_from_path(%{path_info: [locale | _rest]}) when locale in @supported_locales do
    locale
  end

  defp locale_from_path(_conn), do: nil

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  @doc """
  Returns the default locale.
  """
  def default_locale, do: @default_locale
end
