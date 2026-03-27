defmodule Micelio.Auth.GitHubTest do
  use ExUnit.Case, async: true

  alias Micelio.Auth.GitHub

  test "authorize_url/1 builds a GitHub URL with state" do
    assert {:ok, url} = GitHub.authorize_url("state-token")

    assert url =~ "https://github.com/login/oauth/authorize?"
    assert url =~ "client_id=github-client-id"
    assert url =~ "redirect_uri=http%3A%2F%2Flocalhost%3A4002%2Fauth%2Fgithub%2Fcallback"
    assert url =~ "scope=read%3Auser+user%3Aemail"
    assert url =~ "state=state-token"
  end

  test "fetch_user_profile/1 returns normalized profile" do
    assert {:ok, profile} = GitHub.fetch_user_profile("valid-code")

    assert profile.provider == "github"
    assert profile.provider_user_id == "4242"
    assert profile.email == "octocat@example.com"
    assert profile.login == "octocat"
  end

  test "fetch_user_profile/1 returns error for invalid code" do
    assert {:error, :invalid_code} = GitHub.fetch_user_profile("invalid-code")
  end
end
