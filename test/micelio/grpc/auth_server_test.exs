defmodule Micelio.GRPC.AuthServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Auth.V1.DeviceAuthService.Server

  alias Micelio.GRPC.Auth.V1.{
    DeviceAuthorizationRequest,
    DeviceClientRegistrationRequest,
    DeviceTokenRequest
  }

  alias Micelio.OAuth

  test "registers a device client and starts authorization" do
    registration =
      Server.register_device(%DeviceClientRegistrationRequest{name: "mic"}, nil)

    assert registration.client_id != ""
    assert registration.client_secret != ""

    auth =
      Server.start_device_authorization(
        %DeviceAuthorizationRequest{
          client_id: registration.client_id,
          client_secret: registration.client_secret,
          device_name: "test-device",
          scope: ""
        },
        nil
      )

    assert auth.device_code != ""
    assert auth.user_code != ""
    assert auth.verification_uri != ""
  end

  test "exchanges a device code after approval" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-auth@example.com")

    registration =
      Server.register_device(%DeviceClientRegistrationRequest{name: "mic"}, nil)

    auth =
      Server.start_device_authorization(
        %DeviceAuthorizationRequest{
          client_id: registration.client_id,
          client_secret: registration.client_secret,
          device_name: "test-device",
          scope: ""
        },
        nil
      )

    assert {:ok, _grant} = OAuth.approve_device_grant(auth.user_code, user)

    token_response =
      Server.exchange_device_code(
        %DeviceTokenRequest{
          client_id: registration.client_id,
          client_secret: registration.client_secret,
          device_code: auth.device_code
        },
        nil
      )

    assert token_response.access_token != ""
    assert token_response.token_type == "Bearer"
  end
end
