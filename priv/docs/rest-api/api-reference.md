%{
  title: "REST API Reference",
  description: "Endpoints, error format, and usage guide for the Micelio REST API."
}
---

The Micelio REST API provides programmatic access to repositories, sessions, content, and organizations. All endpoints are under `/api/v1/` and return JSON.

## Interactive documentation

Visit [/api/docs](/api/docs) to explore the full OpenAPI specification with Swagger UI. You can try out requests directly from the browser once you have an access token.

## Authentication

The REST API uses the same OAuth2 bearer tokens as the gRPC API. See [Authentication and Authorization](/docs/auth/authentication) for how to obtain and use tokens, and for the full list of scopes.

Include the access token in the `Authorization` header:

```bash
curl https://micelio.example/api/v1/orgs \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## Endpoints overview

### Organizations

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/v1/orgs` | `organizations:read` | List your organizations |
| GET | `/api/v1/orgs/:handle` | `organizations:read` | Get an organization |

### Repositories

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/v1/orgs/:org/repositories` | `repositories:read` | List repositories |
| POST | `/api/v1/orgs/:org/repositories` | `repositories:write` | Create a repository |
| GET | `/api/v1/orgs/:org/repositories/:handle` | `repositories:read` | Get a repository |
| PATCH | `/api/v1/orgs/:org/repositories/:handle` | `repositories:write` | Update a repository |
| DELETE | `/api/v1/orgs/:org/repositories/:handle` | `repositories:write` | Delete a repository |

### Sessions

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/v1/orgs/:org/repositories/:repo/sessions` | `sessions:read` | List sessions |
| POST | `/api/v1/orgs/:org/repositories/:repo/sessions` | `sessions:write` | Start a session |
| GET | `/api/v1/sessions/:session_id` | `sessions:read` | Get a session |
| POST | `/api/v1/sessions/:session_id/land` | `sessions:write` | Land a session |

### Content

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/v1/orgs/:org/repositories/:repo/tree` | `content:read` | List files in a repository |
| GET | `/api/v1/orgs/:org/repositories/:repo/blob/*path` | `content:read` | Get file content |
| GET | `/api/v1/orgs/:org/repositories/:repo/blame/*path` | `content:read` | Get file blame |

## Error format

All errors follow a consistent format:

```json
{
  "error": "not_found",
  "error_description": "Resource not found"
}
```

Common error codes:

| Code | HTTP Status | Meaning |
|---|---|---|
| `unauthorized` | 401 | Missing or invalid token |
| `insufficient_scope` | 403 | Token lacks required scope |
| `forbidden` | 403 | User lacks permission on this resource |
| `not_found` | 404 | Resource does not exist |
| `validation_error` | 422 | Invalid request body (check `errors` field) |

## Rate limiting

API requests are rate-limited per IP (unauthenticated) or per user (authenticated). Authenticated requests get higher limits: 1000 requests per minute vs 100 for unauthenticated. See [Authorization](/docs/auth/authorization) for full details on limits, headers, and abuse protection.

## Examples

### List repositories

```bash
curl https://micelio.example/api/v1/orgs/my-org/repositories \
  -H "Authorization: Bearer TOKEN"
```

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "handle": "my-repo",
      "name": "My Repository",
      "description": "A sample repository",
      "visibility": "private",
      "organization_handle": "my-org",
      "inserted_at": "2026-01-15T10:30:00Z",
      "updated_at": "2026-01-15T10:30:00Z"
    }
  ]
}
```

### Start a session

```bash
curl -X POST https://micelio.example/api/v1/orgs/my-org/repositories/my-repo/sessions \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"goal": "Add user authentication"}'
```

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "goal": "Add user authentication",
    "status": "active",
    "started_at": "2026-01-15T10:35:00Z",
    "landed_at": null,
    "inserted_at": "2026-01-15T10:35:00Z",
    "updated_at": "2026-01-15T10:35:00Z"
  }
}
```

### Get file content

```bash
curl https://micelio.example/api/v1/orgs/my-org/repositories/my-repo/blob/src/main.rs \
  -H "Authorization: Bearer TOKEN"
```

```json
{
  "data": {
    "content": "fn main() {\n    println!(\"Hello, world!\");\n}\n",
    "encoding": "utf-8",
    "size": 46
  }
}
```
