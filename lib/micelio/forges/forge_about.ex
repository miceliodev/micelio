defmodule Micelio.Forges.ForgeAbout do
  @moduledoc false

  @github_accept "application/vnd.github+json"

  def fetch(host, owner, repo, opts \\ [])

  def fetch("github.com", owner, repo, opts) do
    fetch_github(owner, repo, opts)
  end

  def fetch("gitlab.com", owner, repo, opts) do
    fetch_gitlab(owner, repo, opts)
  end

  def fetch(_host, _owner, _repo, _opts), do: {:error, :unsupported_host}

  defp fetch_github(owner, repo, opts) do
    url = "https://api.github.com/repos/#{URI.encode(owner)}/#{URI.encode(repo)}"

    headers =
      [{"accept", @github_accept}, {"user-agent", "Micelio"}]
      |> maybe_put_bearer(Keyword.get(opts, :access_token))

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           description: body["description"],
           url: body["html_url"],
           stars: body["stargazers_count"],
           forks: body["forks_count"],
           watchers: body["subscribers_count"],
           language: body["language"],
           license: get_in(body, ["license", "spdx_id"])
         }}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :access_denied}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: _}} ->
        {:error, :upstream_error}

      {:error, _reason} ->
        {:error, :upstream_unreachable}
    end
  end

  defp fetch_gitlab(owner, repo, opts) do
    encoded_path = URI.encode_www_form("#{owner}/#{repo}")
    url = "https://gitlab.com/api/v4/projects/#{encoded_path}"

    headers =
      [{"accept", "application/json"}, {"user-agent", "Micelio"}]
      |> maybe_put_bearer(Keyword.get(opts, :access_token))

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           description: body["description"],
           url: body["web_url"],
           stars: body["star_count"],
           forks: body["forks_count"],
           watchers: nil,
           language: nil,
           license: nil
         }}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :access_denied}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: _}} ->
        {:error, :upstream_error}

      {:error, _reason} ->
        {:error, :upstream_unreachable}
    end
  end

  defp maybe_put_bearer(headers, token) when is_binary(token) and token != "" do
    [{"authorization", "Bearer #{token}"} | headers]
  end

  defp maybe_put_bearer(headers, _), do: headers
end
