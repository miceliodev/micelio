defmodule Micelio.GRPC.Auth.V1.DeviceClientRegistrationRequest do
  use Protobuf, syntax: :proto3

  field :name, 1, type: :string
end

defmodule Micelio.GRPC.Auth.V1.DeviceClientRegistrationResponse do
  use Protobuf, syntax: :proto3

  field :client_id, 1, type: :string, json_name: "clientId"
  field :client_secret, 2, type: :string, json_name: "clientSecret"
end

defmodule Micelio.GRPC.Auth.V1.DeviceAuthorizationRequest do
  use Protobuf, syntax: :proto3

  field :client_id, 1, type: :string, json_name: "clientId"
  field :client_secret, 2, type: :string, json_name: "clientSecret"
  field :device_name, 3, type: :string, json_name: "deviceName"
  field :scope, 4, type: :string
end

defmodule Micelio.GRPC.Auth.V1.DeviceAuthorizationResponse do
  use Protobuf, syntax: :proto3

  field :device_code, 1, type: :string, json_name: "deviceCode"
  field :user_code, 2, type: :string, json_name: "userCode"
  field :verification_uri, 3, type: :string, json_name: "verificationUri"
  field :verification_uri_complete, 4, type: :string, json_name: "verificationUriComplete"
  field :expires_in, 5, type: :uint32, json_name: "expiresIn"
  field :interval, 6, type: :uint32
end

defmodule Micelio.GRPC.Auth.V1.DeviceTokenRequest do
  use Protobuf, syntax: :proto3

  field :client_id, 1, type: :string, json_name: "clientId"
  field :client_secret, 2, type: :string, json_name: "clientSecret"
  field :device_code, 3, type: :string, json_name: "deviceCode"
end

defmodule Micelio.GRPC.Auth.V1.DeviceTokenResponse do
  use Protobuf, syntax: :proto3

  field :token_type, 1, type: :string, json_name: "tokenType"
  field :access_token, 2, type: :string, json_name: "accessToken"
  field :refresh_token, 3, type: :string, json_name: "refreshToken"
  field :expires_in, 4, type: :uint32, json_name: "expiresIn"
end

defmodule Micelio.GRPC.Auth.V1.DeviceAuthService.Service do
  use GRPC.Service, name: "micelio.auth.v1.DeviceAuthService"

  rpc(
    :RegisterDevice,
    Micelio.GRPC.Auth.V1.DeviceClientRegistrationRequest,
    Micelio.GRPC.Auth.V1.DeviceClientRegistrationResponse
  )

  rpc(
    :StartDeviceAuthorization,
    Micelio.GRPC.Auth.V1.DeviceAuthorizationRequest,
    Micelio.GRPC.Auth.V1.DeviceAuthorizationResponse
  )

  rpc(
    :ExchangeDeviceCode,
    Micelio.GRPC.Auth.V1.DeviceTokenRequest,
    Micelio.GRPC.Auth.V1.DeviceTokenResponse
  )
end

defmodule Micelio.GRPC.Auth.V1.DeviceAuthService.Stub do
  use GRPC.Stub, service: Micelio.GRPC.Auth.V1.DeviceAuthService.Service
end
