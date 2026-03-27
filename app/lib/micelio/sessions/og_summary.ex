defmodule Micelio.Sessions.OGSummary do
  @moduledoc """
  LLM-backed summaries for agent Open Graph images.
  """

  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange

  @max_changes 20

  def config(opts \\ []) do
    :micelio
    |> Application.get_env(__MODULE__, [])
    |> Keyword.merge(opts)
    |> Keyword.put_new(:llm_model, "gpt-4.1-mini")
  end

  def digest(changes) when is_list(changes) do
    changes
    |> Enum.map(&change_signature/1)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  def generate(%Session{} = session, changes, opts \\ []) when is_list(changes) do
    if changes == [] do
      {:error, :no_changes}
    else
      config = config(opts)

      with {:ok, endpoint} <- fetch_config(config, :llm_endpoint),
           {:ok, api_key} <- fetch_config(config, :llm_api_key),
           model = Keyword.get(config, :llm_model, "gpt-4.1-mini"),
           {:ok, response} <- request_summary(endpoint, api_key, model, session, changes) do
        parse_response(response.body)
      end
    end
  end

  defp request_summary(endpoint, api_key, model, session, changes) do
    payload = %{
      model: model,
      input: prompt(session, changes),
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "agent_change_summary",
          schema: %{
            type: "object",
            properties: %{
              summary: %{type: "string"}
            },
            required: ["summary"]
          }
        }
      }
    }

    Req.post(
      endpoint,
      json: payload,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 30_000
    )
  end

  defp parse_response(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> parse_response(decoded)
      {:error, _} -> decode_json_from_text(body)
    end
  end

  defp parse_response(%{"summary" => summary}), do: normalize_summary(summary)
  defp parse_response(%{summary: summary}), do: normalize_summary(summary)

  defp parse_response(%{"output" => _} = payload) do
    text =
      get_in(payload, ["output", Access.at(0), "content", Access.at(0), "text"])

    decode_json_from_text(text)
  end

  defp parse_response(%{"choices" => _} = payload) do
    text = get_in(payload, ["choices", Access.at(0), "message", "content"])
    decode_json_from_text(text)
  end

  defp parse_response(_), do: {:error, :unexpected_response}

  defp decode_json_from_text(nil), do: {:error, :unexpected_response}

  defp decode_json_from_text(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, decoded} -> parse_response(decoded)
      _ -> extract_json_from_text(text)
    end
  end

  defp extract_json_from_text(text) do
    case Regex.run(~r/\{.*\}/s, text) do
      [json] ->
        case JSON.decode(json) do
          {:ok, decoded} -> parse_response(decoded)
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :unexpected_response}
    end
  end

  defp normalize_summary(summary) when is_binary(summary) do
    summary =
      summary
      |> String.replace(~r/[^\x20-\x7E]/u, "")
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    summary =
      if String.length(summary) > 160 do
        String.slice(summary, 0, 160)
      else
        summary
      end

    if summary == "", do: {:error, :empty_summary}, else: {:ok, summary}
  end

  defp normalize_summary(_), do: {:error, :unexpected_response}

  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, {:missing_config, key}}, else: {:ok, trimmed}

      nil ->
        {:error, {:missing_config, key}}
    end
  end

  defp prompt(%Session{} = session, changes) do
    total = length(changes)
    counts = change_counts(changes)

    changes =
      changes
      |> Enum.take(@max_changes)
      |> Enum.map_join("\n", &format_change/1)

    """
    Summarize these agent code changes for an Open Graph description.
    Requirements:
    - 1-2 sentences, 160 characters max.
    - ASCII only, no emojis, no quotes.
    - Focus on what changed in the code, not the process.
    Output JSON: {"summary": "..."}.
    Goal: #{session.goal}
    Total changes: #{total} (added #{counts.added}, modified #{counts.modified}, deleted #{counts.deleted}).
    Changes:
    #{changes}
    """
  end

  defp change_counts(changes) do
    Enum.reduce(changes, %{added: 0, modified: 0, deleted: 0}, fn change, acc ->
      case change.change_type do
        "added" -> %{acc | added: acc.added + 1}
        "modified" -> %{acc | modified: acc.modified + 1}
        "deleted" -> %{acc | deleted: acc.deleted + 1}
        _ -> acc
      end
    end)
  end

  defp format_change(%SessionChange{} = change) do
    "#{change_type_label(change.change_type)} #{change.file_path}"
  end

  defp change_type_label("added"), do: "added"
  defp change_type_label("modified"), do: "modified"
  defp change_type_label("deleted"), do: "deleted"
  defp change_type_label(_), do: "updated"

  defp change_signature(%SessionChange{} = change) do
    content_key =
      cond do
        is_binary(change.storage_key) and change.storage_key != "" ->
          change.storage_key

        is_binary(change.content) and change.content != "" ->
          change.content
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        true ->
          ""
      end

    {change.file_path || "", change.change_type || "", content_key}
  end
end
