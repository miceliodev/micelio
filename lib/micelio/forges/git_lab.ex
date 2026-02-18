defmodule Micelio.Forges.GitLab do
  @moduledoc false

  @accept "application/json"

  def fetch_repository(owner, repo, opts \\ []) do
    owner = String.trim(owner)
    repo = String.trim(repo)
    encoded_path = URI.encode_www_form("#{owner}/#{repo}")
    url = "https://gitlab.com/api/v4/projects/#{encoded_path}"

    headers =
      [
        {"accept", @accept},
        {"user-agent", "Micelio"}
      ]
      |> maybe_put_bearer(Keyword.get(opts, :access_token))

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           name: Map.get(body, "name") || repo,
           description: Map.get(body, "description"),
           url: Map.get(body, "web_url"),
           visibility: map_visibility(Map.get(body, "visibility")),
           forge_owner: owner_from_body(body, owner),
           forge_repo: Map.get(body, "path") || repo,
           forge_external_id: stringify(Map.get(body, "id")),
           forge_default_branch: Map.get(body, "default_branch")
         }}

      {:ok, %{status: 401}} ->
        {:error, :access_denied}

      {:ok, %{status: 403}} ->
        {:error, :access_denied}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: _}} ->
        {:error, :upstream_error}

      {:error, _reason} ->
        {:error, :upstream_unreachable}
    end
  end

  defp map_visibility("public"), do: "public"
  defp map_visibility(_), do: "private"

  defp owner_from_body(body, fallback) do
    case Map.get(body, "path_with_namespace") do
      namespace when is_binary(namespace) and namespace != "" ->
        namespace
        |> String.split("/")
        |> List.first()
        |> case do
          nil -> fallback
          owner -> owner
        end

      _ ->
        fallback
    end
  end

  defp maybe_put_bearer(headers, token) when is_binary(token) and token != "" do
    [{"authorization", "Bearer #{token}"} | headers]
  end

  defp maybe_put_bearer(headers, _), do: headers

  defp stringify(nil), do: nil
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
