%{
  title: "Authorization",
  description: "How scopes and resource-level permissions control access to the REST and gRPC APIs."
}
---

Micelio uses a two-layer authorization model that applies to both the REST API and the gRPC API. The first layer checks token scopes, and the second layer checks resource-level permissions.

## Scopes

Tokens are scoped to control what they can access. Request only the scopes you need when registering a client or authenticating.

### Repositories

| Scope | Description |
|---|---|
| `repositories:read` | List and get repositories |
| `repositories:write` | Create, update, and delete repositories |

### Sessions

| Scope | Description |
|---|---|
| `sessions:read` | List and get sessions |
| `sessions:write` | Start, land, and abandon sessions |

### Content

| Scope | Description |
|---|---|
| `content:read` | Read files, trees, and blame |

### Organizations

| Scope | Description |
|---|---|
| `organizations:read` | List and get organizations |

### Plans

| Scope | Description |
|---|---|
| `plans:read` | List and get plans |
| `plans:write` | Create plans |

### Tokens

| Scope | Description |
|---|---|
| `tokens:read` | Read token pool balance |
| `tokens:write` | Update token pool and contribute tokens |

Multiple scopes are space-separated when requesting them: `"repositories:read sessions:write content:read"`.

## How authorization works

### Layer 1: Scope check

The first check is coarse-grained. It verifies that the token has the right scope for the type of operation being performed. For example, a token with only `repositories:read` cannot create repositories.

If a token lacks the required scope, the API returns a `403` error with `insufficient_scope`.

### Layer 2: Resource authorization

The second check is fine-grained. It verifies that the user has permission on the specific resource being accessed. For example, a user may have `repositories:write` scope but still cannot delete a repository they are not an admin of.

If the token has the scope but the user lacks permission on the specific resource, the API returns a `403` error with `forbidden`.

## Rate limiting

Both APIs enforce rate limits per IP address (unauthenticated) or per user (authenticated). Limits are tracked in memory using ETS.

| Context | Limit | Window |
|---|---|---|
| REST API (unauthenticated) | 100 requests | 1 minute |
| REST API (authenticated) | 1000 requests | 1 minute |
| gRPC API | 100 requests | 1 minute |

Every response includes rate limit headers:

- `x-ratelimit-limit`: Maximum requests allowed in the current window
- `x-ratelimit-remaining`: Requests remaining in the current window
- `retry-after`: Seconds to wait before retrying (only on 429 responses)

When the limit is exceeded, the API returns HTTP `429 Too Many Requests`. Repeated violations (5 within 5 minutes) trigger an abuse block that lasts 1 hour. Abuse-blocked responses include an `x-abuse-blocked: true` header.

## Public vs private repositories

Public repositories can be read without authentication via the gRPC API (when configured to allow it). Private repositories always require a valid token with appropriate scopes.

The REST API always requires authentication for all endpoints.
