defmodule MicelioWeb.AuthorizationPlug do
  def init(opts), do: opts

  def call(conn, _opts) do
    conn
  end
end
