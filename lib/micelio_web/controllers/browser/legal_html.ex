defmodule MicelioWeb.Browser.LegalHTML do
  @moduledoc """
  This module contains pages rendered by LegalController.

  See the `legal_html` directory for all templates available.
  """
  use MicelioWeb, :html
  use Gettext, backend: MicelioWeb.Gettext

  embed_templates "legal_html/*"
end
