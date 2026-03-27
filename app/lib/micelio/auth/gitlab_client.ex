defmodule Micelio.Auth.GitLabClient do
  @callback exchange_code_for_token(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @callback fetch_user(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback fetch_emails(String.t(), map()) :: {:ok, list(map())} | {:error, term()}
end
