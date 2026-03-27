defmodule Micelio.Auth.Passkeys do
  @moduledoc false

  alias Micelio.Accounts.Passkey
  alias Micelio.Auth.WebAuthn
  alias MicelioWeb.Endpoint

  @default_timeout 60_000

  def generate_challenge do
    :crypto.strong_rand_bytes(32)
  end

  def registration_options(user, challenge) do
    %{
      challenge: Base.url_encode64(challenge, padding: false),
      rp: %{name: "Micelio", id: rp_id()},
      user: %{
        id: Base.url_encode64(user.id, padding: false),
        name: user.email,
        displayName: user.account.handle
      },
      pubKeyCredParams: [%{type: "public-key", alg: -7}],
      timeout: @default_timeout,
      attestation: "none",
      authenticatorSelection: %{userVerification: "preferred"}
    }
  end

  def authentication_options(challenge, allow_credentials \\ []) do
    %{
      challenge: Base.url_encode64(challenge, padding: false),
      timeout: @default_timeout,
      userVerification: "preferred",
      allowCredentials: format_allow_credentials(allow_credentials)
    }
  end

  def verify_registration(params, expected_challenge) do
    WebAuthn.verify_registration(params, expected_challenge, rp_id(), origin())
  end

  def verify_authentication(params, expected_challenge, %Passkey{} = passkey) do
    WebAuthn.verify_authentication(
      params,
      expected_challenge,
      rp_id(),
      origin(),
      passkey.public_key,
      passkey.sign_count
    )
  end

  def credential_id_from_params(%{"rawId" => raw_id}) do
    WebAuthn.decode_base64url(raw_id)
  end

  def credential_id_from_params(_), do: {:error, :invalid_credential_id}

  defp format_allow_credentials(passkeys) do
    Enum.map(passkeys, fn passkey ->
      %{
        id: Base.url_encode64(passkey.credential_id, padding: false),
        type: "public-key"
      }
    end)
  end

  defp rp_id do
    Endpoint.config(:url) |> Keyword.get(:host, "localhost")
  end

  defp origin do
    Endpoint.url()
  end
end
