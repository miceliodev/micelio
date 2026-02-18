%{
  title: "REST API Reference",
  description: "Endpoints, error format, and usage guide for the Micelio REST API."
}
---

The Micelio REST API provides programmatic access to repositories, sessions, content, and organizations. All endpoints are under `/api/` and return JSON.

## Authentication

The REST API uses the same OAuth2 bearer tokens as the gRPC API. See [Authentication and Authorization](/docs/auth/authentication) for how to obtain and use tokens, and for the full list of scopes.

Include the access token in the `Authorization` header:

```bash
curl https://micelio.example/api/orgs \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

The interactive examples below use your current browser session, so no token is needed.

## Organizations

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/orgs` | `organizations:read` | List your organizations |
| GET | `/api/orgs/:handle` | `organizations:read` | Get an organization |

### List organizations

```try-it
{"method":"GET","path":"/api/orgs","description":"List organizations you belong to","params":[]}
```

### Get an organization

```try-it
{"method":"GET","path":"/api/orgs/:org","description":"Get details for a single organization","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"}]}
```

## Repositories

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/orgs/:org/repositories` | `repositories:read` | List repositories |
| POST | `/api/orgs/:org/repositories` | `repositories:write` | Create a repository |
| GET | `/api/orgs/:org/repositories/:handle` | `repositories:read` | Get a repository |
| PATCH | `/api/orgs/:org/repositories/:handle` | `repositories:write` | Update a repository |
| DELETE | `/api/orgs/:org/repositories/:handle` | `repositories:write` | Delete a repository |

### List repositories

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories","description":"List all repositories in an organization","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"}]}
```

### Get a repository

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo","description":"Get details for a single repository","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}]}
```

## Sessions

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/orgs/:org/repositories/:repo/sessions` | `sessions:read` | List sessions |
| POST | `/api/orgs/:org/repositories/:repo/sessions` | `sessions:write` | Start a session |
| GET | `/api/sessions/:session_id` | `sessions:read` | Get a session |
| POST | `/api/sessions/:session_id/land` | `sessions:write` | Land a session |

### List sessions

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo/sessions","description":"List all sessions for a repository","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}]}
```

### Start a session

```try-it
{"method":"POST","path":"/api/orgs/:org/repositories/:repo/sessions","description":"Start a new session on a repository","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}],"body":{"goal":"Add user authentication"}}
```

## Plans

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/orgs/:org/repositories/:repo/plans` | `plans:read` | List plans |
| POST | `/api/orgs/:org/repositories/:repo/plans` | `plans:write` | Create a plan |
| GET | `/api/orgs/:org/repositories/:repo/plans/:number` | `plans:read` | Get a plan |
| PATCH | `/api/orgs/:org/repositories/:repo/plans/:number` | `plans:write` | Update a plan |
| POST | `/api/orgs/:org/repositories/:repo/plans/:number/close` | `plans:write` | Close a plan |
| POST | `/api/orgs/:org/repositories/:repo/plans/:number/reopen` | `plans:write` | Reopen a plan |

### List plans

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo/plans","description":"List all plans for a repository","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}]}
```

### Create a plan

```try-it
{"method":"POST","path":"/api/orgs/:org/repositories/:repo/plans","description":"Create a new plan","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}],"body":{"title":"Fix login bug","description":"The login form fails when using special characters in the password"}}
```

### Get a plan

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo/plans/:number","description":"Get a plan by number","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"},{"name":"number","placeholder":"1","description":"Plan number"}]}
```

### Close a plan

```try-it
{"method":"POST","path":"/api/orgs/:org/repositories/:repo/plans/:number/close","description":"Close a plan","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"},{"name":"number","placeholder":"1","description":"Plan number"}]}
```

### Reopen a plan

```try-it
{"method":"POST","path":"/api/orgs/:org/repositories/:repo/plans/:number/reopen","description":"Reopen a closed plan","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"},{"name":"number","placeholder":"1","description":"Plan number"}]}
```

## Content

| Method | Path | Scope | Description |
|---|---|---|---|
| GET | `/api/orgs/:org/repositories/:repo/tree` | `content:read` | List files in a repository |
| GET | `/api/orgs/:org/repositories/:repo/blob/*path` | `content:read` | Get file content |
| GET | `/api/orgs/:org/repositories/:repo/blame/*path` | `content:read` | Get file blame |

### List files

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo/tree","description":"List all files in the repository tree","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"}]}
```

### Get file content

```try-it
{"method":"GET","path":"/api/orgs/:org/repositories/:repo/blob/:path","description":"Read the content of a single file","params":[{"name":"org","placeholder":"my-org","description":"Organization handle"},{"name":"repo","placeholder":"my-repo","description":"Repository handle"},{"name":"path","placeholder":"README.md","description":"File path"}]}
```

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

API requests are rate-limited. See [Authorization](/docs/auth/authorization) for details on limits, headers, and abuse protection.
