defmodule Micelio.Forges.GitHubPullRequests do
  @moduledoc false

  @accept "application/vnd.github+json"

  def ensure_draft_pr(repository, access_token, opts) do
    owner = repository.forge_owner
    repo = repository.forge_repo
    base_branch = repository.forge_default_branch || "main"
    branch_name = Keyword.fetch!(opts, :branch_name)
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description, "")

    with {:ok, base_sha} <- base_branch_sha(owner, repo, base_branch, access_token),
         :ok <- ensure_branch(owner, repo, branch_name, base_sha, access_token),
         {:ok, pull_request} <-
           ensure_pull_request(
             owner,
             repo,
             branch_name,
             base_branch,
             title,
             description,
             access_token
           ) do
      {:ok,
       %{
         provider: "github",
         number: Map.get(pull_request, "number"),
         url: Map.get(pull_request, "html_url"),
         state: map_state(pull_request),
         draft: Map.get(pull_request, "draft", false),
         branch_name: branch_name,
         metadata: %{
           "node_id" => Map.get(pull_request, "node_id")
         }
       }}
    end
  end

  defp base_branch_sha(owner, repo, base_branch, access_token) do
    path = "/repos/#{owner}/#{repo}/git/ref/heads/#{base_branch}"

    with {:ok, body} <- request(:get, path, access_token) do
      case get_in(body, ["object", "sha"]) do
        sha when is_binary(sha) and sha != "" -> {:ok, sha}
        _ -> {:error, :missing_base_branch_sha}
      end
    end
  end

  defp ensure_branch(owner, repo, branch_name, sha, access_token) do
    path = "/repos/#{owner}/#{repo}/git/refs"

    body = %{
      ref: "refs/heads/#{branch_name}",
      sha: sha
    }

    case request(:post, path, access_token, json: body) do
      {:ok, _} ->
        :ok

      {:error, {:unprocessable_entity, _}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_pull_request(
         owner,
         repo,
         branch_name,
         base_branch,
         title,
         description,
         access_token
       ) do
    with {:ok, existing} <- find_existing_pull_request(owner, repo, branch_name, access_token) do
      case existing do
        [pull_request | _] ->
          {:ok, pull_request}

        [] ->
          create_pull_request(
            owner,
            repo,
            branch_name,
            base_branch,
            title,
            description,
            access_token
          )
      end
    end
  end

  defp find_existing_pull_request(owner, repo, branch_name, access_token) do
    path = "/repos/#{owner}/#{repo}/pulls"

    request(:get, path, access_token,
      params: %{
        state: "open",
        head: "#{owner}:#{branch_name}"
      }
    )
  end

  defp create_pull_request(
         owner,
         repo,
         branch_name,
         base_branch,
         title,
         description,
         access_token
       ) do
    path = "/repos/#{owner}/#{repo}/pulls"

    body = %{
      title: title,
      head: branch_name,
      base: base_branch,
      body: description,
      draft: true
    }

    request(:post, path, access_token, json: body)
  end

  defp request(method, path, access_token, opts \\ []) do
    headers = [
      {"accept", @accept},
      {"authorization", "Bearer #{access_token}"},
      {"x-github-api-version", "2022-11-28"}
    ]

    request_opts =
      opts
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, "https://api.github.com" <> path)
      |> Keyword.put(:headers, headers)

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :integration_required}

      {:ok, %{status: 403}} ->
        {:error, :integration_required}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 422, body: body}} ->
        {:error, {:unprocessable_entity, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp map_state(%{"merged_at" => merged_at}) when not is_nil(merged_at), do: "merged"
  defp map_state(%{"state" => "closed"}), do: "closed"
  defp map_state(%{"draft" => true}), do: "draft"
  defp map_state(%{"state" => "open"}), do: "open"
  defp map_state(_), do: "unknown"
end
