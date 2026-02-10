defmodule Micelio.GRPC.Sessions.V1.ConversationMessage do
  use Protobuf, syntax: :proto3

  field :role, 1, type: :string
  field :content, 2, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.Decision do
  use Protobuf, syntax: :proto3

  field :decision, 1, type: :string
  field :reasoning, 2, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.FileChange do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :content, 2, type: :string
  field :change_type, 3, type: :string, json_name: "changeType"
end

defmodule Micelio.GRPC.Sessions.V1.Session do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :goal, 3, type: :string
  field :organization_handle, 4, type: :string, json_name: "organizationHandle"
  field :repository_handle, 5, type: :string, json_name: "projectHandle"
  field :status, 6, type: :string
  field :conversation_count, 7, type: :uint32, json_name: "conversationCount"
  field :decisions_count, 8, type: :uint32, json_name: "decisionsCount"
  field :started_at, 9, type: :string, json_name: "startedAt"
  field :landed_at, 10, type: :string, json_name: "landedAt"
  field :landing_position, 11, type: :uint64, json_name: "landingPosition"
  field :contributor_type, 12, type: :string, json_name: "contributorType"
  field :model_id, 13, type: :string, json_name: "modelId"
  field :tool_name, 14, type: :string, json_name: "toolName"
  field :tool_version, 15, type: :string, json_name: "toolVersion"
end

defmodule Micelio.GRPC.Sessions.V1.StartSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :repository_handle, 3, type: :string, json_name: "projectHandle"
  field :session_id, 4, type: :string, json_name: "sessionId"
  field :goal, 5, type: :string
  field :conversation, 6, repeated: true, type: Micelio.GRPC.Sessions.V1.ConversationMessage
  field :decisions, 7, repeated: true, type: Micelio.GRPC.Sessions.V1.Decision
  field :contributor_type, 8, type: :string, json_name: "contributorType"
  field :model_id, 9, type: :string, json_name: "modelId"
  field :tool_name, 10, type: :string, json_name: "toolName"
  field :tool_version, 11, type: :string, json_name: "toolVersion"
end

defmodule Micelio.GRPC.Sessions.V1.LandSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :conversation, 3, repeated: true, type: Micelio.GRPC.Sessions.V1.ConversationMessage
  field :decisions, 4, repeated: true, type: Micelio.GRPC.Sessions.V1.Decision
  field :files, 5, repeated: true, type: Micelio.GRPC.Sessions.V1.FileChange
  field :epoch, 6, type: :uint32
  field :finalize, 7, type: :bool
end

defmodule Micelio.GRPC.Sessions.V1.GetSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :session_id, 2, type: :string, json_name: "sessionId"
end

defmodule Micelio.GRPC.Sessions.V1.ListSessionsRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :repository_handle, 3, type: :string, json_name: "projectHandle"
  field :status, 4, type: :string
  field :path, 5, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.CaptureSessionEventRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :payload, 3, type: :string
  field :stream, 4, type: :string
  field :format, 5, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.CaptureSessionEventResponse do
  use Protobuf, syntax: :proto3

  field :storage_key, 1, type: :string, json_name: "storageKey"
  field :event_json, 2, type: :string, json_name: "eventJson"
end

defmodule Micelio.GRPC.Sessions.V1.SessionResponse do
  use Protobuf, syntax: :proto3

  field :session, 1, type: Micelio.GRPC.Sessions.V1.Session
end

defmodule Micelio.GRPC.Sessions.V1.ListSessionsResponse do
  use Protobuf, syntax: :proto3

  field :sessions, 1, repeated: true, type: Micelio.GRPC.Sessions.V1.Session
end

defmodule Micelio.GRPC.Sessions.V1.SessionService.Service do
  use GRPC.Service, name: "micelio.sessions.v1.SessionService"

  rpc(
    :StartSession,
    Micelio.GRPC.Sessions.V1.StartSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :LandSession,
    Micelio.GRPC.Sessions.V1.LandSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :GetSession,
    Micelio.GRPC.Sessions.V1.GetSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :ListSessions,
    Micelio.GRPC.Sessions.V1.ListSessionsRequest,
    Micelio.GRPC.Sessions.V1.ListSessionsResponse
  )

  rpc(
    :CaptureSessionEvent,
    Micelio.GRPC.Sessions.V1.CaptureSessionEventRequest,
    Micelio.GRPC.Sessions.V1.CaptureSessionEventResponse
  )
end
