%{
  title: "Authentication",
  description: "How to obtain and use OAuth2 tokens for the REST and gRPC APIs."
}
---

Micelio exposes two APIs: a REST API (`/api/v1/`) and a gRPC API (port 50051). Both use the same OAuth2 bearer tokens for authentication.

## Obtaining a token

### 1. Register a client

Before you can authenticate, you need an OAuth2 client. Use dynamic client registration:

```bash
curl -X POST https://micelio.example/oauth/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "My Tool",
    "grant_types": ["urn:ietf:params:oauth:grant-type:device_code"],
    "scope": "repositories:read sessions:write content:read"
  }'
```

The response includes a `client_id` and `client_secret` that you will use in the next step.

### 2. Device flow authentication

The device flow is designed for CLI tools and environments without a browser. It works in three steps:

**Step 1: Request a device code**

```bash
curl -X POST https://micelio.example/auth/device \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "YOUR_CLIENT_ID",
    "scope": "repositories:read sessions:write content:read"
  }'
```

The response includes:
- `device_code`: Used to poll for the token
- `user_code`: The code the user enters in the browser
- `verification_uri`: The URL where the user authorizes the request
- `expires_in`: How long the codes are valid
- `interval`: How often to poll (in seconds)

**Step 2: User authorizes in browser**

Direct the user to open `verification_uri` and enter the `user_code`. They will log in and approve the requested scopes.

**Step 3: Poll for the token**

```bash
curl -X POST https://micelio.example/oauth/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
    "client_id": "YOUR_CLIENT_ID",
    "device_code": "DEVICE_CODE"
  }'
```

While the user hasn't authorized yet, you will receive `authorization_pending`. Keep polling at the specified interval until you receive an `access_token`.

> [!TIP]
> If multiple processes share the same client credentials (for example, parallel CI jobs or background workers), coordinate token polling so that only one process performs the device flow at a time. Concurrent polling with the same device code can lead to race conditions where one process consumes the token while others receive unexpected errors.

### Using the mic CLI

The `mic` CLI handles this flow automatically:

```bash
mic auth login    # Opens browser, completes device flow
mic auth status   # Verify authentication
```

## Using tokens

### REST API

Include the token in the `Authorization` header:

```bash
curl https://micelio.example/api/v1/orgs \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### gRPC API

Pass the token as gRPC metadata:

```
authorization: Bearer YOUR_ACCESS_TOKEN
```

In the `mic` CLI, the token is stored locally after login and sent automatically with every gRPC call.

## Token lifecycle

The device flow returns a pair of tokens:

- **Access token**: Used to authenticate API requests. Expires after 24 hours.
- **Refresh token**: Used to obtain a new access token without repeating the device flow. Expires after 30 days.

### Refreshing a token

When your access token expires, use the refresh token to get a new one:

```bash
curl -X POST https://micelio.example/oauth/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "refresh_token",
    "client_id": "YOUR_CLIENT_ID",
    "client_secret": "YOUR_CLIENT_SECRET",
    "refresh_token": "YOUR_REFRESH_TOKEN"
  }'
```

The response includes a new `access_token` and `refresh_token` pair.

### Additional notes

- Tokens without explicit scopes (from before scopes were introduced) have access to all scopes for backwards compatibility
- To revoke access, remove the token from your local storage or register a new client
