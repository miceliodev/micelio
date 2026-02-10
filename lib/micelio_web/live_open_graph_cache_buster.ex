defmodule MicelioWeb.LiveOpenGraphCacheBuster do
  @moduledoc """
  Propagates OG cache busters from the session into LiveView page metadata.
  """

  alias MicelioWeb.PageMeta

  def on_mount(:default, _params, session, socket) do
    case Map.get(session, "og_cache_buster") do
      cache_buster when is_binary(cache_buster) and cache_buster != "" ->
        {:cont, PageMeta.assign(socket, open_graph: %{cache_buster: cache_buster})}

      _ ->
        {:cont, socket}
    end
  end
end
