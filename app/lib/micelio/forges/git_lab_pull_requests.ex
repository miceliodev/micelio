defmodule Micelio.Forges.GitLabPullRequests do
  @moduledoc false

  def ensure_draft_pr(repository, access_token, opts) do
    owner = repository.forge_owner
    repo = repository.forge_repo
    base_branch = repository.forge_default_branch || "main"
    branch_name = Keyword.fetch!(opts, :branch_name)
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description, "")
    project_path = URI.encode_www_form("#{owner}/#{repo}")

    with :ok <- ensure_branch(project_path, branch_name, base_branch, access_token),
         {:ok, merge_request} <-
           ensure_merge_request(
             project_path,
             branch_name,
             base_branch,
             title,
             description,
             access_token
           ) do
      {:ok,
       %{
         provider: "gitlab",
         number: Map.get(merge_request, "iid"),
         url: Map.get(merge_request, "web_url"),
         state: map_state(merge_request),
         draft: draft?(merge_request),
         branch_name: branch_name,
         metadata: %{
           "id" => Map.get(merge_request, "id")
         }
       }}
    end
  end

  defp ensure_branch(project_path, branch_name, base_branch, access_token) do
    path = "/projects/#{project_path}/repository/branches"

    case request(:post, path, access_token,
           form: %{
             branch: branch_name,
             ref: base_branch
           }
         ) do
      {:ok, _} ->
        :ok

      {:error, {:bad_request, body}} ->
        message = Map.get(body, "message")

        if is_binary(message) and String.contains?(String.downcase(message), "already exists") do
          :ok
        else
          {:error, {:bad_request, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_merge_request(
         project_path,
         branch_name,
         base_branch,
         title,
         description,
         access_token
       ) do
    with {:ok, existing} <-
           find_existing_merge_request(project_path, branch_name, base_branch, access_token) do
      case existing do
        [merge_request | _] ->
          {:ok, merge_request}

        [] ->
          create_merge_request(
            project_path,
            branch_name,
            base_branch,
            title,
            description,
            access_token
          )
      end
    end
  end

  defp find_existing_merge_request(project_path, branch_name, base_branch, access_token) do
    path = "/projects/#{project_path}/merge_requests"

    request(:get, path, access_token,
      params: %{
        state: "opened",
        source_branch: branch_name,
        target_branch: base_branch
      }
    )
  end

  defp create_merge_request(
         project_path,
         branch_name,
         base_branch,
         title,
         description,
         access_token
       ) do
    path = "/projects/#{project_path}/merge_requests"

    request(:post, path, access_token,
      form: %{
        source_branch: branch_name,
        target_branch: base_branch,
        title: draft_title(title),
        description: description
      }
    )
  end

  defp request(method, path, access_token, opts) do
    headers = [
      {"authorization", "Bearer #{access_token}"}
    ]

    request_opts =
      opts
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, "https://gitlab.com/api/v4" <> path)
      |> Keyword.put(:headers, headers)

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 400, body: body}} ->
        {:error, {:bad_request, body}}

      {:ok, %{status: 401}} ->
        {:error, :integration_required}

      {:ok, %{status: 403}} ->
        {:error, :integration_required}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp draft_title(title) do
    if String.starts_with?(title, "Draft: "), do: title, else: "Draft: " <> title
  end

  defp draft?(%{"draft" => value}) when is_boolean(value), do: value

  defp draft?(%{"work_in_progress" => value}) when is_boolean(value), do: value

  defp draft?(%{"title" => title}) when is_binary(title) do
    String.starts_with?(title, "Draft: ") or String.starts_with?(title, "WIP:")
  end

  defp draft?(_), do: false

  defp map_state(%{"state" => "opened"} = merge_request) do
    if draft?(merge_request), do: "draft", else: "open"
  end

  defp map_state(%{"state" => "merged"}), do: "merged"
  defp map_state(%{"state" => "closed"}), do: "closed"
  defp map_state(_), do: "unknown"
end
