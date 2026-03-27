defmodule RuntimeConfigTest do
  use ExUnit.Case

  describe "SMTP configuration validation logic" do
    test "identifies missing SMTP_HOST" do
      vars = [
        {"SMTP_HOST", nil},
        {"SMTP_USERNAME", "user"},
        {"SMTP_PASSWORD", "pass"}
      ]

      missing =
        vars
        |> Enum.filter(fn {_, val} -> is_nil(val) end)
        |> Enum.map(fn {name, _} -> name end)

      assert ["SMTP_HOST"] = missing
    end

    test "identifies missing SMTP_USERNAME" do
      vars = [
        {"SMTP_HOST", "smtp.example.com"},
        {"SMTP_USERNAME", nil},
        {"SMTP_PASSWORD", "pass"}
      ]

      missing =
        vars
        |> Enum.filter(fn {_, val} -> is_nil(val) end)
        |> Enum.map(fn {name, _} -> name end)

      assert ["SMTP_USERNAME"] = missing
    end

    test "identifies missing SMTP_PASSWORD" do
      vars = [
        {"SMTP_HOST", "smtp.example.com"},
        {"SMTP_USERNAME", "user"},
        {"SMTP_PASSWORD", nil}
      ]

      missing =
        vars
        |> Enum.filter(fn {_, val} -> is_nil(val) end)
        |> Enum.map(fn {name, _} -> name end)

      assert ["SMTP_PASSWORD"] = missing
    end

    test "identifies all missing required SMTP variables" do
      vars = [
        {"SMTP_HOST", nil},
        {"SMTP_USERNAME", nil},
        {"SMTP_PASSWORD", nil}
      ]

      missing =
        vars
        |> Enum.filter(fn {_, val} -> is_nil(val) end)
        |> Enum.map(fn {name, _} -> name end)

      assert Enum.sort(missing) == Enum.sort(["SMTP_HOST", "SMTP_USERNAME", "SMTP_PASSWORD"])
    end

    test "finds no missing variables when all are present" do
      vars = [
        {"SMTP_HOST", "smtp.example.com"},
        {"SMTP_USERNAME", "user"},
        {"SMTP_PASSWORD", "pass"}
      ]

      missing =
        vars
        |> Enum.filter(fn {_, val} -> is_nil(val) end)
        |> Enum.map(fn {name, _} -> name end)

      assert missing == []
    end

    test "formats error message with missing variables" do
      missing_vars = ["SMTP_HOST", "SMTP_PASSWORD"]

      message = """
      Missing required SMTP configuration. The following environment variables are not set:

      #{Enum.map(missing_vars, &"  - #{&1}") |> Enum.join("\n")}
      """

      assert message =~ "SMTP_HOST"
      assert message =~ "SMTP_PASSWORD"
      refute message =~ "SMTP_USERNAME"

      # Check that each missing variable is on its own line with a bullet point
      assert message =~ "  - SMTP_HOST"
      assert message =~ "  - SMTP_PASSWORD"
      refute message =~ "  - SMTP_USERNAME"
    end
  end
end
