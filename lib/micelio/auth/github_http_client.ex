defmodule Micelio.Auth.GitHubHttpClient do
  @behaviour Micelio.Auth.GitHubClient

  @github_accept "application/vnd.github+json"

  @impl true
  def exchange_code_for_token(code, config) do
    params = %{
      client_id: config.client_id,
      client_secret: config.client_secret,
      code: code,
      redirect_uri: config.redirect_uri
    }

    case Req.post(config.token_url, form: params, headers: [{"accept", "application/json"}]) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_user(token, config) do
    headers = [
      {"accept", @github_accept},
      {"authorization", "Bearer #{token}"},
      {"user-agent", "Micelio"}
    ]

    case Req.get(config.user_url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:user_fetch_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_emails(token, config) do
    headers = [
      {"accept", @github_accept},
      {"authorization", "Bearer #{token}"},
      {"user-agent", "Micelio"}
    ]

    case Req.get(config.emails_url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:emails_fetch_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_repositories(token, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 100)
    page = Keyword.get(opts, :page, 1)
    sort = Keyword.get(opts, :sort, "updated")

    headers = [
      {"accept", @github_accept},
      {"authorization", "Bearer #{token}"},
      {"user-agent", "Micelio"}
    ]

    url =
      "https://api.github.com/user/repos?per_page=#{per_page}&page=#{page}&sort=#{sort}&affiliation=owner,collaborator,organization_member"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:repos_fetch_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
