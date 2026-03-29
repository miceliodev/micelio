defmodule Micelio.Blog.People do
  @moduledoc """
  Compile-time registry of allowed blog authors.
  """

  @ruby %{
    id: :ruby,
    name: "Ruby",
    email: nil,
    x_handle: nil,
    mastodon_handle: nil,
    mastodon_url: nil
  }

  @pedro %{
    id: :pedro,
    name: "Pedro Piñera Buendía",
    email: "pedro@ppinera.es",
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

  def gravatar_url(author, size \\ 160)

  def gravatar_url(%{email: email}, size) when is_binary(email) do
    hash =
      email
      |> String.downcase()
      |> String.trim()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "https://gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end

  def gravatar_url(_, _size), do: nil
end
