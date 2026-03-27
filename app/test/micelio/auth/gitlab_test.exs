defmodule Micelio.Auth.GitLabTest do
  use ExUnit.Case, async: true

  alias Micelio.Auth.GitLab

  test "authorize_url/1 builds a GitLab URL with state" do
    assert {:ok, url} = GitLab.authorize_url("state-token")

    assert url =~ "https://gitlab.com/oauth/authorize?"
    assert url =~ "client_id=gitlab-client-id"
    assert url =~ "redirect_uri=http%3A%2F%2Flocalhost%3A4002%2Fauth%2Fgitlab%2Fcallback"
    assert url =~ "response_type=code"
    assert url =~ "scope=read_user+email"
    assert url =~ "state=state-token"
  end

  test "fetch_user_profile/1 returns normalized profile" do
    assert {:ok, profile} = GitLab.fetch_user_profile("valid-code")

    assert profile.provider == "gitlab"
    assert profile.provider_user_id == "7331"
    assert profile.email == "gitlabber@example.com"
    assert profile.login == "gitlabber"
  end

  test "fetch_user_profile/1 returns error for invalid code" do
    assert {:error, :invalid_code} = GitLab.fetch_user_profile("invalid-code")
  end
end
