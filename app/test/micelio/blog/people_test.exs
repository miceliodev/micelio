defmodule Micelio.Blog.PeopleTest do
  use ExUnit.Case, async: true

  alias Micelio.Blog.People

  describe "gravatar_url/2" do
    test "returns gravatar URL with SHA256 hash of email" do
      author = %{email: "pedro@ppinera.es"}
      url = People.gravatar_url(author)

      assert url =~ "https://gravatar.com/avatar/"
      assert url =~ "?s=160&d=identicon"

      # SHA256 of "pedro@ppinera.es" should be deterministic
      hash =
        "pedro@ppinera.es"
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      assert url == "https://gravatar.com/avatar/#{hash}?s=160&d=identicon"
    end

    test "normalizes email to lowercase and trimmed" do
      url1 = People.gravatar_url(%{email: "Pedro@PPinera.es"})
      url2 = People.gravatar_url(%{email: "  pedro@ppinera.es  "})
      url3 = People.gravatar_url(%{email: "pedro@ppinera.es"})

      assert url1 == url3
      assert url2 == url3
    end

    test "accepts custom size" do
      url = People.gravatar_url(%{email: "test@example.com"}, 120)
      assert url =~ "?s=120&d=identicon"
    end

    test "returns nil when email is nil" do
      assert People.gravatar_url(%{email: nil}) == nil
    end

    test "returns nil when author has no email key" do
      assert People.gravatar_url(%{name: "No Email"}) == nil
    end
  end
end
