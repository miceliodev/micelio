defmodule MicelioWeb.ForgeMount do
  @moduledoc """
  LiveView on_mount hook that assigns `forge_host` to the socket.
  Used in forge-prefixed live_session blocks to tell the RepositoryResolver
  which forge host to use for resolution.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(forge_host, _params, _session, socket) do
    {:cont, assign(socket, :forge_host, forge_host)}
  end
end
