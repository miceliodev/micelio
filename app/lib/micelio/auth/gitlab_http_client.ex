defmodule Micelio.Auth.GitLabHttpClient do
  @behaviour Micelio.Auth.GitLabClient

  @gitlab_accept "application/json"

  @impl true
  def exchange_code_for_token(code, config) do
    params = %{
      client_id: config.client_id,
      client_secret: config.client_secret,
      code: code,
      redirect_uri: config.redirect_uri,
      grant_type: "authorization_code"
    }

    case Req.post(config.token_url, form: params, headers: [{"accept", @gitlab_accept}]) do
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
      {"accept", @gitlab_accept},
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
      {"accept", @gitlab_accept},
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
end
