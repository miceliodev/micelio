defmodule Micelio.Forges.GitHub do
  @moduledoc false

  @accept "application/vnd.github+json"

  def fetch_repository(owner, repo, opts \\ []) do
    owner = String.trim(owner)
    repo = String.trim(repo)

    url = "https://api.github.com/repos/#{owner}/#{repo}"

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
           url: Map.get(body, "html_url"),
           visibility: if(Map.get(body, "private") == true, do: "private", else: "public"),
           forge_owner: owner_from_body(body, owner),
           forge_repo: Map.get(body, "name") || repo,
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

  defp owner_from_body(body, fallback) do
    case Map.get(body, "owner") do
      %{"login" => login} when is_binary(login) and login != "" -> login
      _ -> fallback
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
