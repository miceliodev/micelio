defmodule Micelio.GRPC.Hif.V1.RepositoryRef do
  use Protobuf, syntax: :proto3

  field :account_handle, 1, type: :string, json_name: "accountHandle"
  field :repository_handle, 2, type: :string, json_name: "repositoryHandle"
end

defmodule Micelio.GRPC.Hif.V1.Position do
  use Protobuf, syntax: :proto3

  field :hash, 1, type: :bytes
  field :at, 2, type: :string
end

defmodule Micelio.GRPC.Hif.V1.RepositoryHeadResponse do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :head, 2, type: Micelio.GRPC.Hif.V1.Position
  field :head_etag, 3, type: :string, json_name: "headEtag"
end

defmodule Micelio.GRPC.Hif.V1.GetRepositoryHeadRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
end

defmodule Micelio.GRPC.Hif.V1.GetHeadAtRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :revision_hash, 2, type: :bytes, json_name: "revisionHash"
end

defmodule Micelio.GRPC.Hif.V1.IdentityRef do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :acct, 2, type: :string
  field :handle, 3, type: :string
  field :instance, 4, type: :string
  field :kind, 5, type: :string
end

defmodule Micelio.GRPC.Hif.V1.Attribution do
  use Protobuf, syntax: :proto3

  field :attributed_to, 1, type: Micelio.GRPC.Hif.V1.IdentityRef, json_name: "attributedTo"
  field :performed_by, 2, type: Micelio.GRPC.Hif.V1.IdentityRef, json_name: "performedBy"
end

defmodule Micelio.GRPC.Hif.V1.SessionEvent do
  use Protobuf, syntax: :proto3

  field :role, 1, type: :string
  field :kind, 2, type: :string
  field :text, 3, type: :string
  field :metadata, 4, type: :bytes
  field :at_ms, 5, type: :uint64, json_name: "atMs"
end

defmodule Micelio.GRPC.Hif.V1.FileOperation.Action do
  use Protobuf, enum: true, syntax: :proto3

  field :ACTION_UNSPECIFIED, 0
  field :ACTION_CREATE, 1
  field :ACTION_UPDATE, 2
  field :ACTION_DELETE, 3
  field :ACTION_RENAME, 4
end

defmodule Micelio.GRPC.Hif.V1.FileOperation do
  use Protobuf, syntax: :proto3

  field :action, 1,
    type: Micelio.GRPC.Hif.V1.FileOperation.Action,
    enum: true

  field :path, 2, type: :string
  field :content, 3, type: :bytes
  field :old_path, 4, type: :string, json_name: "oldPath"
  field :content_hash, 5, type: :string, json_name: "contentHash"
end

defmodule Micelio.GRPC.Hif.V1.SessionOpen do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :goal, 2, type: :string
  field :base_position, 3, type: Micelio.GRPC.Hif.V1.Position, json_name: "basePosition"
  field :requested_workspace, 4, type: :string, json_name: "requestedWorkspace"
end

defmodule Micelio.GRPC.Hif.V1.SessionConflict do
  use Protobuf, syntax: :proto3

  field :revision_hash, 1, type: :bytes, json_name: "revisionHash"
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :reason, 3, type: :string
  field :paths, 4, repeated: true, type: :string
end

defmodule Micelio.GRPC.Hif.V1.SessionInfo do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :repository, 2, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :goal, 3, type: :string
  field :status, 4, type: :string
  field :base_position, 5, type: Micelio.GRPC.Hif.V1.Position, json_name: "basePosition"

  field :current_position, 6,
    type: Micelio.GRPC.Hif.V1.Position,
    json_name: "currentPosition"

  field :conversation, 7, repeated: true, type: Micelio.GRPC.Hif.V1.SessionEvent
  field :decisions, 8, repeated: true, type: Micelio.GRPC.Hif.V1.SessionEvent
  field :changes, 9, repeated: true, type: Micelio.GRPC.Hif.V1.FileOperation
  field :attribution, 10, type: Micelio.GRPC.Hif.V1.Attribution
  field :created_at_ms, 11, type: :uint64, json_name: "createdAtMs"
  field :updated_at_ms, 12, type: :uint64, json_name: "updatedAtMs"
  field :conflict, 13, type: Micelio.GRPC.Hif.V1.SessionConflict
end

defmodule Micelio.GRPC.Hif.V1.SessionOpenRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :open, 2, type: Micelio.GRPC.Hif.V1.SessionOpen
end

defmodule Micelio.GRPC.Hif.V1.SessionRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
end

defmodule Micelio.GRPC.Hif.V1.SessionSummary do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :goal, 2, type: :string
  field :attributed_to, 3, type: Micelio.GRPC.Hif.V1.IdentityRef, json_name: "attributedTo"
  field :revision_hash, 4, type: :bytes, json_name: "revisionHash"
end

defmodule Micelio.GRPC.Hif.V1.ListSessionsRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :path, 2, type: :string
  field :limit, 3, type: :uint32
end

defmodule Micelio.GRPC.Hif.V1.ListSessionsResponse do
  use Protobuf, syntax: :proto3

  field :sessions, 1, repeated: true, type: Micelio.GRPC.Hif.V1.SessionSummary
end

defmodule Micelio.GRPC.Hif.V1.SessionSummary do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :goal, 2, type: :string
  field :author, 3, type: :string
  field :position, 4, type: :uint64
end

defmodule Micelio.GRPC.Hif.V1.ListSessionsRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :repository, 2, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :path, 3, type: :string
  field :limit, 4, type: :uint32
end

defmodule Micelio.GRPC.Hif.V1.ListSessionsResponse do
  use Protobuf, syntax: :proto3

  field :sessions, 1, repeated: true, type: Micelio.GRPC.Hif.V1.SessionSummary
end

defmodule Micelio.GRPC.Hif.V1.SessionEventAppendRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :event, 2, type: Micelio.GRPC.Hif.V1.SessionEvent
end

defmodule Micelio.GRPC.Hif.V1.SessionChangeAppendRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :operation, 2, type: Micelio.GRPC.Hif.V1.FileOperation
end

defmodule Micelio.GRPC.Hif.V1.SessionChangesReplaceRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :operations, 2, repeated: true, type: Micelio.GRPC.Hif.V1.FileOperation
  field :epoch, 3, type: :uint32
end

defmodule Micelio.GRPC.Hif.V1.LandSessionRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :decision, 2, repeated: true, type: Micelio.GRPC.Hif.V1.SessionEvent
  field :finalize, 3, type: :bool
  field :epoch, 4, type: :uint32
  field :force, 5, type: :bool
end

defmodule Micelio.GRPC.Hif.V1.AbandonSessionRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
end

defmodule Micelio.GRPC.Hif.V1.TreeEntry do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :hash, 2, type: :string
end

defmodule Micelio.GRPC.Hif.V1.TreeResponse do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :tree_hash, 2, type: :bytes, json_name: "treeHash"
  field :entries, 3, repeated: true, type: Micelio.GRPC.Hif.V1.TreeEntry
end

defmodule Micelio.GRPC.Hif.V1.GetTreeRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :revision_hash, 2, type: :bytes, json_name: "revisionHash"
end

defmodule Micelio.GRPC.Hif.V1.GetPathRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :revision_hash, 2, type: :bytes, json_name: "revisionHash"
  field :path, 3, type: :string
end

defmodule Micelio.GRPC.Hif.V1.PathResponse do
  use Protobuf, syntax: :proto3

  field :content, 1, type: :bytes
  field :content_hash, 2, type: :bytes, json_name: "contentHash"
  field :mode, 3, type: :uint32
  field :size, 4, type: :uint64
end

defmodule Micelio.GRPC.Hif.V1.GetBlobRequest do
  use Protobuf, syntax: :proto3

  field :content_hash, 1, type: :bytes, json_name: "contentHash"
end

defmodule Micelio.GRPC.Hif.V1.BlobResponse do
  use Protobuf, syntax: :proto3

  field :content, 1, type: :bytes
end

defmodule Micelio.GRPC.Hif.V1.DiffRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :from_revision_hash, 2, type: :bytes, json_name: "fromRevisionHash"
  field :to_revision_hash, 3, type: :bytes, json_name: "toRevisionHash"
  field :path_prefix, 4, type: :string, json_name: "pathPrefix"
end

defmodule Micelio.GRPC.Hif.V1.DiffHunk do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :line, 2, type: :uint32
  field :old_line, 3, type: :string, json_name: "oldLine"
  field :new_line, 4, type: :string, json_name: "newLine"
end

defmodule Micelio.GRPC.Hif.V1.DiffResponse do
  use Protobuf, syntax: :proto3

  field :hunks, 1, repeated: true, type: Micelio.GRPC.Hif.V1.DiffHunk
end

defmodule Micelio.GRPC.Hif.V1.BlameLine do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :line, 2, type: :uint32
  field :text, 3, type: :string
  field :session_id, 4, type: :string, json_name: "sessionId"
  field :attributed_to, 5, type: Micelio.GRPC.Hif.V1.IdentityRef, json_name: "attributedTo"
  field :revision_hash, 6, type: :bytes, json_name: "revisionHash"
  field :landed_at, 7, type: :uint64, json_name: "landedAt"
end

defmodule Micelio.GRPC.Hif.V1.BlameRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :revision_hash, 2, type: :bytes, json_name: "revisionHash"
  field :path, 3, type: :string
end

defmodule Micelio.GRPC.Hif.V1.BlameResponse do
  use Protobuf, syntax: :proto3

  field :lines, 1, repeated: true, type: Micelio.GRPC.Hif.V1.BlameLine
end

defmodule Micelio.GRPC.Hif.V1.TextQueryRequest do
  use Protobuf, syntax: :proto3

  field :repository, 1, type: Micelio.GRPC.Hif.V1.RepositoryRef
  field :query, 2, type: :string
  field :at_revision_hash, 3, type: :bytes, json_name: "atRevisionHash"
  field :path_prefix, 4, type: :string, json_name: "pathPrefix"
  field :path_glob, 5, type: :string, json_name: "pathGlob"
  field :regex, 6, type: :bool
  field :case_sensitive, 7, type: :bool, json_name: "caseSensitive"
  field :language_hint, 8, type: :string, json_name: "languageHint"
  field :limit, 9, type: :uint32
  field :offset, 10, type: :uint32
  field :page_token, 11, type: :bytes, json_name: "pageToken"
end

defmodule Micelio.GRPC.Hif.V1.TextQueryMatch do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :line, 2, type: :uint32
  field :column, 3, type: :uint32
  field :snippet, 4, type: :string
  field :session_id, 5, type: :string, json_name: "sessionId"
  field :attributed_to, 6, type: Micelio.GRPC.Hif.V1.IdentityRef, json_name: "attributedTo"
  field :revision_hash, 7, type: :bytes, json_name: "revisionHash"
  field :revision_etag, 8, type: :string, json_name: "revisionEtag"
end

defmodule Micelio.GRPC.Hif.V1.TextQueryResponse do
  use Protobuf, syntax: :proto3

  field :total, 1, type: :uint64
  field :matches, 2, repeated: true, type: Micelio.GRPC.Hif.V1.TextQueryMatch
  field :next_page_token, 3, type: :bytes, json_name: "nextPageToken"
end

defmodule Micelio.GRPC.Hif.V1.VersioningService.Service do
  use GRPC.Service, name: "hif.v1.VersioningService"

  rpc(
    :GetRepositoryHead,
    Micelio.GRPC.Hif.V1.GetRepositoryHeadRequest,
    Micelio.GRPC.Hif.V1.RepositoryHeadResponse
  )

  rpc(
    :GetHeadAt,
    Micelio.GRPC.Hif.V1.GetHeadAtRequest,
    Micelio.GRPC.Hif.V1.RepositoryHeadResponse
  )

  rpc(
    :ListSessions,
    Micelio.GRPC.Hif.V1.ListSessionsRequest,
    Micelio.GRPC.Hif.V1.ListSessionsResponse
  )

  rpc(
    :OpenSession,
    Micelio.GRPC.Hif.V1.SessionOpenRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :AppendSessionConversation,
    Micelio.GRPC.Hif.V1.SessionEventAppendRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :AppendSessionChange,
    Micelio.GRPC.Hif.V1.SessionChangeAppendRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :ReplaceSessionChanges,
    Micelio.GRPC.Hif.V1.SessionChangesReplaceRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :LandSession,
    Micelio.GRPC.Hif.V1.LandSessionRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :AbandonSession,
    Micelio.GRPC.Hif.V1.AbandonSessionRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )

  rpc(
    :GetSession,
    Micelio.GRPC.Hif.V1.SessionRequest,
    Micelio.GRPC.Hif.V1.SessionInfo
  )
end

defmodule Micelio.GRPC.Hif.V1.ContentService.Service do
  use GRPC.Service, name: "hif.v1.ContentService"

  rpc(:GetTree, Micelio.GRPC.Hif.V1.GetTreeRequest, Micelio.GRPC.Hif.V1.TreeResponse)

  rpc(:GetPath, Micelio.GRPC.Hif.V1.GetPathRequest, Micelio.GRPC.Hif.V1.PathResponse)

  rpc(:GetBlob, Micelio.GRPC.Hif.V1.GetBlobRequest, Micelio.GRPC.Hif.V1.BlobResponse)

  rpc(:Diff, Micelio.GRPC.Hif.V1.DiffRequest, Micelio.GRPC.Hif.V1.DiffResponse)

  rpc(:Blame, Micelio.GRPC.Hif.V1.BlameRequest, Micelio.GRPC.Hif.V1.BlameResponse)
end

defmodule Micelio.GRPC.Hif.V1.SearchService.Service do
  use GRPC.Service, name: "hif.v1.SearchService"

  rpc(
    :QueryText,
    Micelio.GRPC.Hif.V1.TextQueryRequest,
    Micelio.GRPC.Hif.V1.TextQueryResponse
  )
end
