defmodule MicelioWeb.Browser.TotpHTML do
  @moduledoc """
  HTML templates for TOTP authentication pages.
  """

  use MicelioWeb, :html

  embed_templates "totp_html/*"
end
