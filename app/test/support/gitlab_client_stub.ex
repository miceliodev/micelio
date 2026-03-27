defmodule Micelio.Auth.GitLabClientStub do
  @behaviour Micelio.Auth.GitLabClient

  @impl true
  def exchange_code_for_token("valid-code", _config), do: {:ok, "valid-token"}
  def exchange_code_for_token(_code, _config), do: {:error, :invalid_code}

  @impl true
  def fetch_user("valid-token", _config) do
    {:ok, %{"id" => 7331, "username" => "gitlabber", "email" => nil}}
  end

  def fetch_user(_token, _config), do: {:error, :invalid_token}

  @impl true
  def fetch_emails("valid-token", _config) do
    {:ok,
     [
       %{"email" => "gitlabber@example.com", "primary" => true, "confirmed" => true}
     ]}
  end

  def fetch_emails(_token, _config), do: {:error, :invalid_token}
end
