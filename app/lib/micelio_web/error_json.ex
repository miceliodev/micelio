defmodule MicelioWeb.ErrorJSON do
  @moduledoc false

  defdelegate render(template, assigns), to: MicelioWeb.Browser.ErrorJSON
end
