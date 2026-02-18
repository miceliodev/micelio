defmodule Micelio.Plans.ACPRedactor do
  @moduledoc false

  @redacted_value "[REDACTED]"
  @sensitive_key_patterns [
    "token",
    "secret",
    "password",
    "authorization",
    "cookie",
    "api_key",
    "apikey",
    "private_key",
    "bearer"
  ]

  def redact(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      redacted =
        if sensitive_key?(key) do
          @redacted_value
        else
          redact(nested_value)
        end

      Map.put(acc, key, redacted)
    end)
  end

  def redact(value) when is_list(value) do
    Enum.map(value, &redact/1)
  end

  def redact(value) when is_binary(value) do
    redact_binary(value)
  end

  def redact(value), do: value

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))

  defp sensitive_key?(key) when is_binary(key) do
    normalized =
      key
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.any?(@sensitive_key_patterns, &String.contains?(normalized, &1))
  end

  defp sensitive_key?(_), do: false

  defp redact_binary(value) do
    trimmed = String.trim(value)

    cond do
      String.starts_with?(String.downcase(trimmed), "bearer ") ->
        "Bearer #{@redacted_value}"

      String.match?(trimmed, ~r/^(gh[pousr]_[A-Za-z0-9_]+)$/) ->
        @redacted_value

      String.match?(trimmed, ~r/^glpat-[A-Za-z0-9\-_]+$/) ->
        @redacted_value

      true ->
        value
    end
  end
end
