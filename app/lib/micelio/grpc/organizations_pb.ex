defmodule Micelio.GRPC.Organizations.V1.Organization do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :handle, 2, type: :string
  field :name, 3, type: :string
  field :description, 4, type: :string
  field :inserted_at, 5, type: :string, json_name: "insertedAt"
  field :updated_at, 6, type: :string, json_name: "updatedAt"
end

defmodule Micelio.GRPC.Organizations.V1.ListOrganizationsRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
end

defmodule Micelio.GRPC.Organizations.V1.ListOrganizationsResponse do
  use Protobuf, syntax: :proto3

  field :organizations, 1, repeated: true, type: Micelio.GRPC.Organizations.V1.Organization
end

defmodule Micelio.GRPC.Organizations.V1.GetOrganizationRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :handle, 2, type: :string
end

defmodule Micelio.GRPC.Organizations.V1.OrganizationResponse do
  use Protobuf, syntax: :proto3

  field :organization, 1, type: Micelio.GRPC.Organizations.V1.Organization
end

defmodule Micelio.GRPC.Organizations.V1.OrganizationService.Service do
  use GRPC.Service, name: "micelio.organizations.v1.OrganizationService"

  rpc(
    :ListOrganizations,
    Micelio.GRPC.Organizations.V1.ListOrganizationsRequest,
    Micelio.GRPC.Organizations.V1.ListOrganizationsResponse
  )

  rpc(
    :GetOrganization,
    Micelio.GRPC.Organizations.V1.GetOrganizationRequest,
    Micelio.GRPC.Organizations.V1.OrganizationResponse
  )
end
