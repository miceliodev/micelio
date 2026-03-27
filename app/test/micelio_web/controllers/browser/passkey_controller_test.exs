defmodule MicelioWeb.Browser.PasskeyControllerTest do
  use MicelioWeb.ConnCase, async: true

  import Bitwise
  import Plug.Conn

  alias Micelio.Accounts
  alias Plug.CSRFProtection

  describe "passkey registration" do
    setup :register_and_log_in_user

    test "registers a passkey", %{conn: conn, user: user} do
      conn =
        conn
        |> with_csrf()
        |> post("/account/passkeys/options", %{})

      assert %{"challenge" => challenge} = json_response(conn, 200)

      {public_key, _private_key} = :crypto.generate_key(:ecdh, :secp256r1)
      credential_id = :crypto.strong_rand_bytes(16)

      payload =
        build_registration_payload(
          challenge,
          credential_id,
          public_key,
          origin(),
          rp_id()
        )

      assert {:ok, _} = Micelio.Auth.Passkeys.verify_registration(payload, challenge)

      conn =
        conn
        |> recycle()
        |> with_csrf()
        |> post("/account/passkeys", payload)

      assert %{"status" => "ok"} = json_response(conn, 200)

      assert %Accounts.Passkey{user_id: user_id} =
               Accounts.get_passkey_by_credential_id(credential_id)

      assert user_id == user.id
    end
  end

  describe "passkey authentication" do
    setup %{conn: conn} do
      {:ok, user} = Accounts.get_or_create_user_by_email("passkey-user@example.com")
      %{conn: conn, user: user}
    end

    test "authenticates a passkey", %{conn: conn, user: user} do
      {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)
      credential_id = :crypto.strong_rand_bytes(16)

      {:ok, passkey} =
        Accounts.create_passkey(user, %{
          credential_id: credential_id,
          public_key: public_key,
          sign_count: 0,
          name: "Test Passkey"
        })

      conn =
        conn
        |> with_csrf()
        |> post("/auth/passkey/options", %{})

      assert %{"challenge" => challenge} = json_response(conn, 200)

      payload =
        build_authentication_payload(
          challenge,
          credential_id,
          private_key,
          origin(),
          rp_id()
        )

      conn =
        conn
        |> recycle()
        |> with_csrf()
        |> post("/auth/passkey/authenticate", payload)

      assert %{"status" => "ok", "redirect_to" => "/"} = json_response(conn, 200)
      assert get_session(conn, :user_id) == passkey.user_id
    end
  end

  defp build_registration_payload(challenge, credential_id, public_key, origin, rp_id) do
    client_data = %{
      "type" => "webauthn.create",
      "challenge" => challenge,
      "origin" => origin
    }

    client_data_json = Jason.encode!(client_data)

    flags = 0x41
    sign_count = 0
    rp_id_hash = :crypto.hash(:sha256, rp_id)

    auth_data =
      rp_id_hash <>
        <<flags::unsigned-8, sign_count::unsigned-big-32>> <>
        :binary.copy(<<0>>, 16) <>
        <<byte_size(credential_id)::unsigned-big-16>> <>
        credential_id <>
        cbor_encode(cose_key(public_key))

    attestation_object =
      cbor_encode(%{
        "fmt" => "none",
        "authData" => {:bytes, auth_data},
        "attStmt" => %{}
      })

    %{
      "id" => base64url(credential_id),
      "rawId" => base64url(credential_id),
      "type" => "public-key",
      "response" => %{
        "attestationObject" => base64url(attestation_object),
        "clientDataJSON" => base64url(client_data_json)
      }
    }
  end

  defp build_authentication_payload(challenge, credential_id, private_key, origin, rp_id) do
    client_data = %{
      "type" => "webauthn.get",
      "challenge" => challenge,
      "origin" => origin
    }

    client_data_json = Jason.encode!(client_data)

    flags = 0x01
    sign_count = 1
    rp_id_hash = :crypto.hash(:sha256, rp_id)

    authenticator_data =
      rp_id_hash <> <<flags::unsigned-8, sign_count::unsigned-big-32>>

    signed_data = authenticator_data <> :crypto.hash(:sha256, client_data_json)

    signature = :crypto.sign(:ecdsa, :sha256, signed_data, [private_key, :secp256r1])

    %{
      "id" => base64url(credential_id),
      "rawId" => base64url(credential_id),
      "type" => "public-key",
      "response" => %{
        "clientDataJSON" => base64url(client_data_json),
        "authenticatorData" => base64url(authenticator_data),
        "signature" => base64url(signature)
      }
    }
  end

  defp cose_key(<<4, x::bytes-size(32), y::bytes-size(32)>>) do
    %{1 => 2, 3 => -7, -1 => 1, -2 => {:bytes, x}, -3 => {:bytes, y}}
  end

  defp base64url(data) when is_binary(data) do
    Base.url_encode64(data, padding: false)
  end

  defp cbor_encode(term) when is_integer(term) and term >= 0 do
    encode_major(0, term)
  end

  defp cbor_encode(term) when is_integer(term) and term < 0 do
    encode_major(1, -1 - term)
  end

  defp cbor_encode({:bytes, term}) when is_binary(term) do
    encode_major(2, byte_size(term)) <> term
  end

  defp cbor_encode(term) when is_binary(term) do
    if String.valid?(term) do
      encode_major(3, byte_size(term)) <> term
    else
      encode_major(2, byte_size(term)) <> term
    end
  end

  defp cbor_encode(term) when is_list(term) do
    payload = Enum.map_join(term, "", &cbor_encode/1)
    encode_major(4, length(term)) <> payload
  end

  defp cbor_encode(term) when is_map(term) do
    entries = Enum.map(term, fn {key, value} -> cbor_encode(key) <> cbor_encode(value) end)
    encode_major(5, map_size(term)) <> Enum.join(entries, "")
  end

  defp encode_major(major, value) when value < 24 do
    <<(major <<< 5) + value>>
  end

  defp encode_major(major, value) when value < 0x100 do
    <<(major <<< 5) + 24, value::unsigned-8>>
  end

  defp encode_major(major, value) when value < 0x10000 do
    <<(major <<< 5) + 25, value::unsigned-big-16>>
  end

  defp encode_major(major, value) when value < 0x1_0000_0000 do
    <<(major <<< 5) + 26, value::unsigned-big-32>>
  end

  defp encode_major(major, value) do
    <<(major <<< 5) + 27, value::unsigned-big-64>>
  end

  defp with_csrf(conn) do
    csrf_token = CSRFProtection.get_csrf_token()
    existing_session = Map.get(conn.private, :plug_session, %{})

    conn
    |> Plug.Test.init_test_session(existing_session)
    |> put_session("_csrf_token", CSRFProtection.dump_state())
    |> put_req_header("x-csrf-token", csrf_token)
  end

  defp rp_id do
    MicelioWeb.Endpoint.config(:url)
    |> Keyword.get(:host, "localhost")
  end

  defp origin do
    MicelioWeb.Endpoint.url()
  end
end
