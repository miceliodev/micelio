defmodule Micelio.Sandboxes.Token do
  @moduledoc """
  Generates and validates per-sandbox bearer tokens for module serving.

  Tokens are stored in `sandbox_metadata["sandbox_token"]` on the Plan schema
  and validated by `MicelioWeb.Plugs.SandboxTokenPlug` when Deno fetches modules.
  """

  @token_bytes 32

  @doc """
  Generate a new cryptographically secure sandbox token.
  """
  def generate do
    :crypto.strong_rand_bytes(@token_bytes)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Validate a provided token against the stored token in a plan's sandbox metadata.

  Uses constant-time comparison to prevent timing attacks.
  """
  def valid?(provided_token, %{sandbox_metadata: %{"sandbox_token" => stored_token}})
      when is_binary(provided_token) and is_binary(stored_token) do
    Plug.Crypto.secure_compare(provided_token, stored_token)
  end

  def valid?(_, _), do: false
end
