defmodule Micelio.Blog.People do
  @moduledoc """
  Compile-time registry of allowed blog authors.
  """

  @ruby %{
    id: :ruby,
    name: "Ruby",
    x_handle: nil,
    mastodon_handle: nil,
    mastodon_url: nil
  }

  @pedro %{
    id: :pedro,
    name: "Pedro Piñera Buendía",
    x_handle: "pepicrft",
    mastodon_handle: "@pedro@mastodon.pepicrft.me",
    mastodon_url: "https://mastodon.pepicrft.me/@pedro"
  }

  @people %{
    ruby: @ruby,
    pedro: @pedro
  }

  def all, do: Map.values(@people)

  def get!(id) when is_atom(id), do: Map.fetch!(@people, id)

  def name!(id) when is_atom(id) do
    id |> get!() |> Map.fetch!(:name)
  end
end
