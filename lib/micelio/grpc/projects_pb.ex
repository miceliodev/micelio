defmodule Micelio.GRPC.Repositories.V1.Project do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :organization_id, 2, type: :string, json_name: "organizationId"
  field :organization_handle, 3, type: :string, json_name: "organizationHandle"
  field :handle, 4, type: :string
  field :name, 5, type: :string
  field :description, 6, type: :string
  field :inserted_at, 7, type: :string, json_name: "insertedAt"
  field :updated_at, 8, type: :string, json_name: "updatedAt"
  field :visibility, 9, type: :string
end

defmodule Micelio.GRPC.Repositories.V1.ListProjectsRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
end

defmodule Micelio.GRPC.Repositories.V1.ListProjectsResponse do
  use Protobuf, syntax: :proto3

  field :repositories, 1, repeated: true, type: Micelio.GRPC.Repositories.V1.Project
end

defmodule Micelio.GRPC.Repositories.V1.GetProjectRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :handle, 3, type: :string
end

defmodule Micelio.GRPC.Repositories.V1.CreateProjectRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :handle, 3, type: :string
  field :name, 4, type: :string
  field :description, 5, type: :string
  field :visibility, 6, type: :string
end

defmodule Micelio.GRPC.Repositories.V1.UpdateProjectRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :handle, 3, type: :string
  field :new_handle, 4, type: :string, json_name: "newHandle"
  field :name, 5, type: :string
  field :description, 6, type: :string
  field :visibility, 7, type: :string
end

defmodule Micelio.GRPC.Repositories.V1.DeleteProjectRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :handle, 3, type: :string
end

defmodule Micelio.GRPC.Repositories.V1.ProjectResponse do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Repositories.V1.Project
end

defmodule Micelio.GRPC.Repositories.V1.DeleteProjectResponse do
  use Protobuf, syntax: :proto3

  field :success, 1, type: :bool
end

defmodule Micelio.GRPC.Repositories.V1.ProjectService.Service do
  use GRPC.Service, name: "micelio.repositories.v1.ProjectService"

  rpc(
    :ListProjects,
    Micelio.GRPC.Repositories.V1.ListProjectsRequest,
    Micelio.GRPC.Repositories.V1.ListProjectsResponse
  )

  rpc(
    :GetProject,
    Micelio.GRPC.Repositories.V1.GetProjectRequest,
    Micelio.GRPC.Repositories.V1.ProjectResponse
  )

  rpc(
    :CreateProject,
    Micelio.GRPC.Repositories.V1.CreateProjectRequest,
    Micelio.GRPC.Repositories.V1.ProjectResponse
  )

  rpc(
    :UpdateProject,
    Micelio.GRPC.Repositories.V1.UpdateProjectRequest,
    Micelio.GRPC.Repositories.V1.ProjectResponse
  )

  rpc(
    :DeleteProject,
    Micelio.GRPC.Repositories.V1.DeleteProjectRequest,
    Micelio.GRPC.Repositories.V1.DeleteProjectResponse
  )
end
