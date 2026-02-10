defmodule Micelio.Security.SecretScanner do
  @moduledoc """
  Detects high-confidence secrets in session changes.
  """

  alias Micelio.Sessions
  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  @max_files_to_report 5
  @aws_access_key_example "AKIAIOSFODNN7EXAMPLE"

  @patterns [
    {:aws_access_key_id, ~r/\b(AKIA|ASIA)[0-9A-Z]{16}\b/},
    {:aws_secret_access_key,
     ~r/\b(?:AWS_SECRET_ACCESS_KEY|aws_secret_access_key|s3_secret_access_key)\s*[:=]\s*["']?([A-Za-z0-9\/+=]{40})["']?/},
    {:github_token, ~r/\bghp_[A-Za-z0-9]{36}\b/},
    {:github_pat, ~r/\bgithub_pat_[A-Za-z0-9_]{20,}\b/},
    {:gitlab_pat, ~r/\bglpat-[A-Za-z0-9\-_]{20,}\b/},
    {:slack_token, ~r/\bxox(?:b|p|a|r|s)-[A-Za-z0-9-]{10,}\b/},
    {:stripe_secret, ~r/\bsk_live_[0-9a-zA-Z]{20,}\b/},
    {:private_key, ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/}
  ]

  # Paths that are excluded from secret scanning (test files often contain fake secrets)
  @excluded_paths [
    ~r{^test/},
    ~r{_test\.exs?$}
  ]

  def scan_session_changes(%Session{} = session) do
    hits =
      session
      |> Sessions.list_session_changes()
      |> Enum.reduce(%{}, fn change, acc ->
        if excluded_path?(change.file_path) do
          acc
        else
          case load_change_content(change) do
            content when is_binary(content) ->
              if text_content?(content) do
                types = scan_content(content)

                if types == [] do
                  acc
                else
                  Map.update(acc, change.file_path, MapSet.new(types), fn existing ->
                    Enum.reduce(types, existing, &MapSet.put(&2, &1))
                  end)
                end
              else
                acc
              end

            _ ->
              acc
          end
        end
      end)

    if map_size(hits) == 0 do
      :ok
    else
      files = hits |> Map.keys() |> Enum.sort()
      {:error, %{files: files, matches: hits}}
    end
  end

  def format_scan_error(%{files: files}) do
    display = files |> Enum.take(@max_files_to_report) |> Enum.join(", ")
    overflow = length(files) - @max_files_to_report

    if overflow > 0 do
      "Potential secrets detected in session changes: #{display} (and #{overflow} more)"
    else
      "Potential secrets detected in session changes: #{display}"
    end
  end

  defp scan_content(content) when is_binary(content) do
    Enum.reduce(@patterns, [], fn {type, regex}, acc ->
      if Regex.match?(regex, content) and not ignore_match?(type, content, regex) do
        [type | acc]
      else
        acc
      end
    end)
  end

  defp ignore_match?(:aws_access_key_id, content, regex) do
    Regex.scan(regex, content)
    |> Enum.any?(fn
      [match, _prefix] -> match == @aws_access_key_example
      [match] -> match == @aws_access_key_example
    end)
  end

  # Ignore test tokens that are clearly fake (all digits or obvious test patterns)
  defp ignore_match?(:github_token, content, regex) do
    Regex.scan(regex, content)
    |> Enum.all?(fn [match] ->
      # Extract the part after ghp_
      token = String.replace_prefix(match, "ghp_", "")
      # Ignore if it's all digits (obviously fake) or contains "test/example" patterns
      Regex.match?(~r/^[0-9]+$/, token) or
        String.contains?(String.downcase(token), "test") or
        String.contains?(String.downcase(token), "example")
    end)
  end

  defp ignore_match?(_type, _content, _regex), do: false

  defp load_change_content(%SessionChange{change_type: "deleted"}), do: nil

  defp load_change_content(%SessionChange{content: content}) when is_binary(content), do: content

  defp load_change_content(%SessionChange{storage_key: key}) when is_binary(key) do
    case Storage.get(key) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp load_change_content(_change), do: nil

  defp text_content?(content) when is_binary(content) do
    String.valid?(content) and not String.contains?(content, <<0>>)
  end

  defp excluded_path?(path) when is_binary(path) do
    Enum.any?(@excluded_paths, fn regex -> Regex.match?(regex, path) end)
  end

  defp excluded_path?(_), do: false
end
