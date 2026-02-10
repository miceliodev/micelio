defmodule Micelio.Auth.GitHub do
  @moduledoc """
  GitHub OAuth helper functions.
  """

  @default_authorize_url "https://github.com/login/oauth/authorize"
  @default_token_url "https://github.com/login/oauth/access_token"
  @default_user_url "https://api.github.com/user"
  @default_emails_url "https://api.github.com/user/emails"

  @scope "read:user user:email repo"

  def authorize_url(state) when is_binary(state) do
    with {:ok, config} <- oauth_config() do
      query =
        URI.encode_query(%{
          "client_id" => config.client_id,
          "redirect_uri" => config.redirect_uri,
          "scope" => @scope,
          "state" => state
        })

      {:ok, config.authorize_url <> "?" <> query}
    end
  end

  def fetch_user_profile(code) when is_binary(code) do
    with {:ok, config} <- oauth_config(),
         {:ok, token} <- config.http_client.exchange_code_for_token(code, config),
         {:ok, user} <- config.http_client.fetch_user(token, config),
         {:ok, email} <- resolve_email(user, token, config),
         {:ok, provider_user_id} <- normalize_provider_user_id(user) do
      {:ok,
       %{
         provider: "github",
         provider_user_id: provider_user_id,
         email: email,
         login: Map.get(user, "login"),
         access_token: token
       }}
    end
  end

  defp oauth_config do
    config = Application.get_env(:micelio, :github_oauth, [])

    client_id = Keyword.get(config, :client_id)
    client_secret = Keyword.get(config, :client_secret)
    redirect_uri = Keyword.get(config, :redirect_uri)

    if is_binary(client_id) and is_binary(client_secret) and is_binary(redirect_uri) do
      {:ok,
       %{
         client_id: client_id,
         client_secret: client_secret,
         redirect_uri: redirect_uri,
         authorize_url: Keyword.get(config, :authorize_url, @default_authorize_url),
         token_url: Keyword.get(config, :token_url, @default_token_url),
         user_url: Keyword.get(config, :user_url, @default_user_url),
         emails_url: Keyword.get(config, :emails_url, @default_emails_url),
         http_client: Keyword.get(config, :http_client, Micelio.Auth.GitHubHttpClient)
       }}
    else
      {:error, :github_oauth_not_configured}
    end
  end

  defp resolve_email(%{"email" => email} = user, token, config) when is_binary(email) do
    trimmed = String.trim(email)

    if trimmed == "" do
      resolve_email(Map.delete(user, "email"), token, config)
    else
      {:ok, String.downcase(trimmed)}
    end
  end

  defp resolve_email(_user, token, config) do
    with {:ok, emails} <- config.http_client.fetch_emails(token, config),
         %{"email" => email} <- select_primary_email(emails) do
      {:ok, String.downcase(email)}
    else
      nil -> {:error, :email_not_available}
      {:error, reason} -> {:error, reason}
    end
  end

  defp select_primary_email(emails) do
    Enum.find(emails, fn email ->
      Map.get(email, "primary") == true and Map.get(email, "verified") == true
    end)
  end

  defp normalize_provider_user_id(%{"id" => id}) when is_integer(id) do
    {:ok, Integer.to_string(id)}
  end

  defp normalize_provider_user_id(%{"id" => id}) when is_binary(id) do
    trimmed = String.trim(id)

    if trimmed == "" do
      {:error, :missing_provider_user_id}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_provider_user_id(_user) do
    {:error, :missing_provider_user_id}
  end
end
