defmodule MicelioWeb.ErrorHTML do
  @moduledoc """
  Error HTML controller alias.
  Delegates to MicelioWeb.Browser.ErrorHTML for compatibility.
  """
  defdelegate render(template, assigns), to: MicelioWeb.Browser.ErrorHTML
end
