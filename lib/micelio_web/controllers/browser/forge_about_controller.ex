defmodule MicelioWeb.Browser.ForgeAboutController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Forges.ForgeAboutCache

  def show(conn, %{"host" => host, "owner" => owner, "repo" => repo}) do
    opts = access_token_opts(conn.assigns[:current_user], host)

    case ForgeAboutCache.get_or_fetch(host, owner, repo, opts) do
      {:ok, data} ->
        json(conn, data)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      {:error, _reason} ->
        conn |> put_status(502) |> json(%{error: "upstream_error"})
    end
  end

  defp access_token_opts(nil, _host), do: []

  defp access_token_opts(user, host) do
    provider = provider_for_host(host)

    case provider && Accounts.get_oauth_identity_for_user(user, provider) do
      %{access_token_encrypted: token} when is_binary(token) and token != "" ->
        [access_token: token]

      _ ->
        []
    end
  end

  defp provider_for_host("github.com"), do: :github
  defp provider_for_host("gitlab.com"), do: :gitlab
  defp provider_for_host(_), do: nil
end
