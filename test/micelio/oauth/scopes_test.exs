defmodule Micelio.OAuth.ScopesTest do
  use ExUnit.Case, async: true

  alias Micelio.OAuth.Scopes

  describe "all/0" do
    test "returns Boruta scope structs for all scopes" do
      scopes = Scopes.all()
      assert is_list(scopes)
      refute Enum.empty?(scopes)

      for scope <- scopes do
        assert %Boruta.Oauth.Scope{} = scope
        assert is_binary(scope.name)
      end
    end
  end

  describe "names/0" do
    test "returns all scope names as strings" do
      names = Scopes.names()
      assert is_list(names)
      assert "repositories:read" in names
      assert "repositories:write" in names
      assert "sessions:read" in names
      assert "sessions:write" in names
      assert "content:read" in names
      assert "organizations:read" in names
      assert "plans:read" in names
      assert "plans:write" in names
      assert "tokens:read" in names
      assert "tokens:write" in names
    end
  end

  describe "valid?/1" do
    test "returns true for valid scope names" do
      assert Scopes.valid?("repositories:read")
      assert Scopes.valid?("sessions:write")
      assert Scopes.valid?("content:read")
    end

    test "returns false for invalid scope names" do
      refute Scopes.valid?("invalid:scope")
      refute Scopes.valid?("repositories:admin")
      refute Scopes.valid?("")
    end
  end

  describe "from_string/1" do
    test "returns all scopes when nil" do
      assert Scopes.from_string(nil) == Scopes.names()
    end

    test "returns all scopes when empty string" do
      assert Scopes.from_string("") == Scopes.names()
    end

    test "parses space-separated scope string" do
      result = Scopes.from_string("repositories:read sessions:write")
      assert result == ["repositories:read", "sessions:write"]
    end

    test "filters out invalid scopes" do
      result = Scopes.from_string("repositories:read invalid:scope sessions:write")
      assert result == ["repositories:read", "sessions:write"]
    end

    test "handles extra whitespace" do
      result = Scopes.from_string("  repositories:read   sessions:write  ")
      assert result == ["repositories:read", "sessions:write"]
    end
  end

  describe "descriptions/0" do
    test "returns a map of scope name to description" do
      descriptions = Scopes.descriptions()
      assert is_map(descriptions)
      assert descriptions["repositories:read"] == "List and get repositories"
      assert descriptions["content:read"] == "Read files, trees, and blame"
    end
  end

  describe "definitions/0" do
    test "returns scope definitions with name and description" do
      definitions = Scopes.definitions()
      assert is_list(definitions)

      for definition <- definitions do
        assert is_map(definition)
        assert Map.has_key?(definition, :name)
        assert Map.has_key?(definition, :description)
      end
    end
  end
end
