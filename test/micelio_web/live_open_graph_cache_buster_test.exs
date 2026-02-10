defmodule MicelioWeb.LiveOpenGraphCacheBusterTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.LiveOpenGraphCacheBuster
  alias MicelioWeb.PageMeta

  test "assigns cache buster from session into page meta" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    {:cont, socket} =
      LiveOpenGraphCacheBuster.on_mount(
        :default,
        %{},
        %{"og_cache_buster" => "twitter-99"},
        socket
      )

    meta = PageMeta.from_assigns(socket.assigns)

    assert meta.open_graph[:cache_buster] == "twitter-99"
  end

  test "no-ops when session has no cache buster" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    {:cont, socket} = LiveOpenGraphCacheBuster.on_mount(:default, %{}, %{}, socket)

    meta = PageMeta.from_assigns(socket.assigns)

    assert meta.open_graph == %{}
  end
end
