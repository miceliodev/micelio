defmodule MicelioWeb.PageMetaTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.PageMeta

  test "returns custom og image without modification when present" do
    meta = %PageMeta{
      title_parts: ["Demo"],
      canonical_url: "https://example.com/demo",
      open_graph: %{
        image: "https://assets.example.com/og/demo.png?foo=bar"
      }
    }

    og = PageMeta.open_graph(meta)
    image = Map.get(og, :image) || Map.get(og, "image") || Map.get(og, "og:image")

    assert image == "https://assets.example.com/og/demo.png?foo=bar"
  end
end
