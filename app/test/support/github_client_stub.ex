defmodule Micelio.Auth.GitHubClientStub do
  @behaviour Micelio.Auth.GitHubClient

  @impl true
  def exchange_code_for_token("valid-code", _config), do: {:ok, "valid-token"}
  def exchange_code_for_token(_code, _config), do: {:error, :invalid_code}

  @impl true
  def fetch_user("valid-token", _config) do
    {:ok, %{"id" => 4242, "login" => "octocat", "email" => nil}}
  end

  def fetch_user(_token, _config), do: {:error, :invalid_token}

  @impl true
  def fetch_emails("valid-token", _config) do
    {:ok,
     [
       %{"email" => "octocat@example.com", "primary" => true, "verified" => true}
     ]}
  end

  def fetch_emails(_token, _config), do: {:error, :invalid_token}

  @impl true
  def fetch_repositories("valid-token", _opts) do
    {:ok,
     [
       %{
         "id" => 1,
         "full_name" => "octocat/hello-world",
         "clone_url" => "https://github.com/octocat/hello-world.git",
         "private" => false,
         "description" => "A test repository"
       }
     ]}
  end

  def fetch_repositories(_token, _opts), do: {:error, :invalid_token}
end
