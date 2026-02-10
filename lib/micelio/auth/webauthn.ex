defmodule Micelio.Auth.WebAuthn do
  @moduledoc false

  import Bitwise

  alias Micelio.Auth.CBOR

  def verify_registration(params, expected_challenge, rp_id, origin) do
    with {:ok, client_data, raw_client_data} <- decode_client_data(params),
         :ok <- validate_client_data(client_data, expected_challenge, origin, "webauthn.create"),
         {:ok, attestation} <- decode_attestation_object(params),
         {:ok, auth_data} <- parse_attested_auth_data(attestation),
         :ok <- validate_rp_id(auth_data.rp_id_hash, rp_id),
         :ok <- validate_user_present(auth_data.flags),
         {:ok, public_key} <- cose_to_public_key(auth_data.credential_public_key) do
      {:ok,
       %{
         credential_id: auth_data.credential_id,
         public_key: public_key,
         sign_count: auth_data.sign_count,
         client_data: raw_client_data
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_attestation}
    end
  end

  def verify_authentication(
        params,
        expected_challenge,
        rp_id,
        origin,
        public_key,
        stored_sign_count
      ) do
    with {:ok, client_data, raw_client_data} <- decode_client_data(params),
         :ok <- validate_client_data(client_data, expected_challenge, origin, "webauthn.get"),
         {:ok, auth_data} <- decode_authenticator_data(params),
         :ok <- validate_rp_id(auth_data.rp_id_hash, rp_id),
         :ok <- validate_user_present(auth_data.flags),
         :ok <- validate_signature(auth_data.raw, raw_client_data, params, public_key),
         :ok <- validate_sign_count(stored_sign_count, auth_data.sign_count) do
      {:ok, %{sign_count: auth_data.sign_count}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_assertion}
    end
  end

  def decode_base64url(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_client_data(%{"response" => %{"clientDataJSON" => client_data}}) do
    with {:ok, raw} <- decode_base64url(client_data),
         {:ok, decoded} <- Jason.decode(raw) do
      {:ok, decoded, raw}
    else
      _ -> {:error, :invalid_client_data}
    end
  end

  defp decode_client_data(_), do: {:error, :invalid_client_data}

  defp validate_client_data(client_data, expected_challenge, origin, expected_type) do
    cond do
      Map.get(client_data, "type") != expected_type ->
        {:error, :invalid_type}

      Map.get(client_data, "challenge") != expected_challenge ->
        {:error, :invalid_challenge}

      Map.get(client_data, "origin") != origin ->
        {:error, :invalid_origin}

      true ->
        :ok
    end
  end

  defp decode_attestation_object(%{"response" => %{"attestationObject" => attestation}}) do
    with {:ok, decoded} <- decode_base64url(attestation),
         {:ok, map, rest} <- CBOR.decode(decoded),
         true <- rest == <<>>,
         %{"authData" => auth_data} <- map do
      {:ok, %{auth_data: auth_data}}
    else
      _ -> {:error, :invalid_attestation}
    end
  end

  defp decode_attestation_object(_), do: {:error, :invalid_attestation}

  defp parse_attested_auth_data(%{auth_data: auth_data}) when is_binary(auth_data) do
    with {:ok, %{rp_id_hash: rp_id_hash, flags: flags, sign_count: sign_count, rest: rest}} <-
           parse_authenticator_header(auth_data),
         true <- attested_data_flag?(flags),
         {:ok, credential_id, public_key} <- parse_attested_credential(rest) do
      {:ok,
       %{
         rp_id_hash: rp_id_hash,
         flags: flags,
         sign_count: sign_count,
         credential_id: credential_id,
         credential_public_key: public_key
       }}
    else
      _ -> {:error, :invalid_attestation}
    end
  end

  defp parse_authenticator_header(
         <<rp_id_hash::binary-size(32), flags::unsigned-8, sign_count::unsigned-big-32,
           rest::binary>>
       ) do
    {:ok, %{rp_id_hash: rp_id_hash, flags: flags, sign_count: sign_count, rest: rest}}
  end

  defp parse_authenticator_header(_), do: {:error, :invalid_auth_data}

  defp parse_attested_credential(
         <<_aaguid::binary-size(16), credential_length::unsigned-big-16, rest::binary>>
       ) do
    with <<credential_id::binary-size(credential_length), rest::binary>> <- rest,
         {:ok, cose_key, _rest} <- CBOR.decode(rest) do
      {:ok, credential_id, cose_key}
    else
      _ -> {:error, :invalid_attested_credential}
    end
  end

  defp parse_attested_credential(_), do: {:error, :invalid_attested_credential}

  defp decode_authenticator_data(%{"response" => %{"authenticatorData" => auth_data}}) do
    with {:ok, raw} <- decode_base64url(auth_data),
         {:ok, header} <- parse_authenticator_header(raw) do
      {:ok, Map.put(header, :raw, raw)}
    end
  end

  defp decode_authenticator_data(_), do: {:error, :invalid_auth_data}

  defp validate_rp_id(rp_id_hash, rp_id) do
    expected = :crypto.hash(:sha256, rp_id)

    if expected == rp_id_hash do
      :ok
    else
      {:error, :invalid_rp_id}
    end
  end

  defp validate_user_present(flags) do
    if (flags &&& 0x01) == 0x01 do
      :ok
    else
      {:error, :user_not_present}
    end
  end

  defp validate_signature(auth_data, client_data, params, public_key) do
    with {:ok, signature} <- decode_signature(params),
         signed_data = auth_data <> :crypto.hash(:sha256, client_data),
         true <- :crypto.verify(:ecdsa, :sha256, signed_data, signature, [public_key, :secp256r1]) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp decode_signature(%{"response" => %{"signature" => signature}}) do
    decode_base64url(signature)
  end

  defp decode_signature(_), do: {:error, :invalid_signature}

  defp validate_sign_count(stored, incoming) when incoming == 0 or stored == 0, do: :ok

  defp validate_sign_count(stored, incoming) when incoming > stored, do: :ok

  defp validate_sign_count(_, _), do: {:error, :invalid_sign_count}

  defp attested_data_flag?(flags), do: (flags &&& 0x40) == 0x40

  defp cose_to_public_key(%{1 => 2, 3 => -7, -1 => 1, -2 => x, -3 => y})
       when is_binary(x) and is_binary(y) and byte_size(x) == 32 and byte_size(y) == 32 do
    {:ok, <<4, x::binary, y::binary>>}
  end

  defp cose_to_public_key(_), do: {:error, :unsupported_key}
end
