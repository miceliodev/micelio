defmodule MicelioWeb.SchemaOrgTest do
  use ExUnit.Case, async: true

  alias Micelio.Accounts.Account
  alias Micelio.Repositories.Repository
  alias MicelioWeb.SchemaOrg

  test "builds software source code schema for organization accounts" do
    account = %Account{handle: "acme", organization_id: Ecto.UUID.generate()}
    repository = %Repository{handle: "demo", name: "Demo", description: "A demo repository"}

    schema =
      SchemaOrg.software_source_code(account, repository,
        url: "https://micelio.dev/acme/demo",
        code_repository: "https://micelio.dev/acme/demo",
        author_url: "https://micelio.dev/acme"
      )

    assert schema["@type"] == "SoftwareSourceCode"
    assert schema["identifier"] == "acme/demo"
    assert schema["codeRepository"] == "https://micelio.dev/acme/demo"
    assert schema["author"]["@type"] == "Organization"
  end

  test "encodes schema and omits blank fields" do
    account = %Account{handle: "jane", user_id: Ecto.UUID.generate()}
    repository = %Repository{handle: "demo", name: "Demo", description: nil}

    schema =
      SchemaOrg.software_source_code(account, repository, url: "https://micelio.dev/jane/demo")

    refute Map.has_key?(schema, "description")

    schema
    |> SchemaOrg.encode()
    |> Jason.decode!()
    |> then(fn decoded ->
      assert decoded["author"]["@type"] == "Person"
      assert decoded["url"] == "https://micelio.dev/jane/demo"
    end)
  end
end
