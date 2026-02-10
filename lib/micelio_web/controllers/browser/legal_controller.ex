defmodule MicelioWeb.Browser.LegalController do
  use MicelioWeb, :controller

  alias MicelioWeb.PageMeta

  def privacy(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Privacy Policy"],
      description: "Plain-language summary of how Micelio handles data.",
      canonical_url: url(~p"/privacy")
    )
    |> render(:privacy)
  end

  def terms(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Terms of Service"],
      description: "Plain-language terms for using the Micelio service.",
      canonical_url: url(~p"/terms")
    )
    |> render(:terms)
  end

  def cookies(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Cookie Policy"],
      description: "Minimal notice about essential cookies used by Micelio.",
      canonical_url: url(~p"/cookies")
    )
    |> render(:cookies)
  end

  def impressum(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Impressum"],
      description: "Provider information for Micelio (Germany).",
      canonical_url: url(~p"/impressum")
    )
    |> render(:impressum)
  end
end
