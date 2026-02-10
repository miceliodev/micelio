//! Authentication commands.
//!
//! Implements OAuth 2.0 Device Authorization Grant (RFC 8628) for CLI authentication.

use crate::cli::{AuthCommand, AuthSubcommand};
use crate::config::{self, Config, StoredTokens};
use crate::constants::{
    is_first_party_url, DEVICE_CODE_EXPIRY_SECS, DEVICE_POLL_DEFAULT_INTERVAL_SECS,
    DEVICE_POLL_MIN_INTERVAL_SECS, FIRST_PARTY_CLIENT_ID,
};
use crate::error::{MicError, Result};
use crate::http_client;
use colored::Colorize;
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Run the auth command.
pub async fn run(cmd: AuthCommand) -> Result<()> {
    match cmd.command {
        AuthSubcommand::Login => login().await,
        AuthSubcommand::Status => status(),
        AuthSubcommand::Logout => logout(),
    }
}

// =============================================================================
// Device Flow Types
// =============================================================================

/// Device authorization response from the server.
#[derive(Debug, Deserialize)]
struct DeviceAuthResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    verification_uri_complete: Option<String>,
    expires_in: Option<i64>,
    interval: Option<i64>,
}

/// Token response after successful authorization.
#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    token_type: String,
    expires_in: Option<i64>,
}

/// Error response from the server.
#[derive(Debug, Deserialize)]
struct ErrorResponse {
    code: String,
    #[allow(dead_code)]
    message: Option<String>,
}

/// Start device authorization request.
#[derive(Debug, Serialize)]
struct StartRequest {
    device_name: String,
    client_id: Option<String>,
}

/// Poll for token request.
#[derive(Debug, Serialize)]
struct PollRequest {
    device_code: String,
}

// =============================================================================
// Commands
// =============================================================================

/// Perform device flow login.
async fn login() -> Result<()> {
    let config = Config::load()?;
    let (server_name, server) = get_default_server(&config)?;
    
    let web_url = server.web_url.as_ref().ok_or(MicError::NoWebUrl)?;
    let grpc_url = server.grpc_url.as_ref().ok_or(MicError::NoGrpcUrl)?;

    // Determine client ID
    let client_id = resolve_client_id(&server, web_url);

    // Start device authorization
    let auth = start_device_authorization(web_url, client_id.as_deref()).await?;
    
    // Display instructions
    print_authorization_instructions(&auth);

    // Poll for token
    let token = poll_for_token(web_url, &auth).await?;

    // Store tokens
    let stored = create_stored_tokens(grpc_url, token);
    config::store_tokens(&stored)?;

    println!("{} Authenticated with {}.", "✓".green(), server_name);
    Ok(())
}

/// Show authentication status.
fn status() -> Result<()> {
    match config::read_tokens()? {
        None => {
            println!("Not logged in.");
            println!("\nRun {} to authenticate.", "mic auth login".cyan());
        }
        Some(tokens) => {
            if is_token_expired(&tokens) {
                println!("{} Access token expired.", "✗".red());
                println!("\nRun {} to re-authenticate.", "mic auth login".cyan());
            } else {
                println!("{} Authenticated with {}.", "✓".green(), tokens.server);
                
                if let Some(expires_at) = tokens.expires_at {
                    let remaining = expires_at - chrono::Utc::now().timestamp();
                    if remaining > 0 {
                        let hours = remaining / 3600;
                        let minutes = (remaining % 3600) / 60;
                        println!("  Token expires in {}h {}m.", hours, minutes);
                    }
                }
            }
        }
    }
    Ok(())
}

/// Log out (remove stored credentials).
fn logout() -> Result<()> {
    config::delete_tokens()?;
    println!("{} Logged out.", "✓".green());
    Ok(())
}

// =============================================================================
// Helpers
// =============================================================================

/// Get the default server configuration.
fn get_default_server(config: &Config) -> Result<(&str, &config::ServerConfig)> {
    let name = config
        .get_default_server_name()
        .ok_or(MicError::NoDefaultServer)?;
    
    let server = config
        .get_server(name)
        .ok_or(MicError::NoDefaultServer)?;
    
    Ok((name, server))
}

/// Resolve the client ID for authentication.
fn resolve_client_id(server: &config::ServerConfig, web_url: &str) -> Option<String> {
    if let Some(ref id) = server.client_id {
        Some(id.clone())
    } else if is_first_party_url(web_url) {
        Some(FIRST_PARTY_CLIENT_ID.to_string())
    } else {
        None
    }
}

/// Start device authorization flow.
async fn start_device_authorization(
    web_url: &str,
    client_id: Option<&str>,
) -> Result<DeviceAuthResponse> {
    let client = http_client::create_client();
    let device_name = get_device_name();
    let start_url = format!("{}/auth/device", web_url);

    let request = StartRequest {
        device_name,
        client_id: client_id.map(String::from),
    };

    let response = http_client::post_json(&client, &start_url, &request).await?;

    if response.status != reqwest::StatusCode::OK {
        return Err(MicError::AuthorizationFailed(format!(
            "Server returned {}",
            response.status
        )));
    }

    serde_json::from_str(&response.body).map_err(|e| {
        MicError::AuthorizationFailed(format!("Invalid server response: {}", e))
    })
}

/// Get the device name for authentication.
fn get_device_name() -> String {
    let hostname = hostname::get()
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|_| "device".to_string());
    format!("mic@{}", hostname)
}

/// Print authorization instructions to the user.
fn print_authorization_instructions(auth: &DeviceAuthResponse) {
    let url = auth
        .verification_uri_complete
        .as_ref()
        .unwrap_or(&auth.verification_uri);

    println!();
    println!("Open this URL in your browser:");
    println!("  {}", url.cyan());
    println!();
    println!("Enter code: {}", auth.user_code.bold());
    println!();
    println!("Waiting for authorization...");
}

/// Poll for token after device authorization.
async fn poll_for_token(web_url: &str, auth: &DeviceAuthResponse) -> Result<TokenResponse> {
    let client = http_client::create_client();
    let poll_url = format!("{}/auth/device", web_url);
    
    let expires_at = chrono::Utc::now().timestamp() 
        + auth.expires_in.unwrap_or(DEVICE_CODE_EXPIRY_SECS);
    let mut interval = auth
        .interval
        .unwrap_or(DEVICE_POLL_DEFAULT_INTERVAL_SECS)
        .max(DEVICE_POLL_MIN_INTERVAL_SECS);

    loop {
        // Check expiry
        if chrono::Utc::now().timestamp() >= expires_at {
            return Err(MicError::DeviceCodeExpired);
        }

        // Wait before polling
        tokio::time::sleep(Duration::from_secs(interval as u64)).await;

        // Poll for token
        let poll_request = PollRequest {
            device_code: auth.device_code.clone(),
        };

        let response = http_client::post_json(&client, &poll_url, &poll_request).await?;

        match response.status {
            reqwest::StatusCode::OK => {
                return serde_json::from_str(&response.body).map_err(|e| {
                    MicError::AuthorizationFailed(format!("Invalid token response: {}", e))
                });
            }
            reqwest::StatusCode::ACCEPTED => {
                // Still waiting, continue polling
                continue;
            }
            _ => {
                // Check error response
                if let Ok(error) = serde_json::from_str::<ErrorResponse>(&response.body) {
                    match error.code.as_str() {
                        "authorization_pending" => continue,
                        "slow_down" => {
                            interval += 5;
                            continue;
                        }
                        "expired_token" => return Err(MicError::DeviceCodeExpired),
                        code => {
                            return Err(MicError::AuthorizationFailed(format!(
                                "Server error: {}",
                                code
                            )));
                        }
                    }
                }
                return Err(MicError::AuthorizationFailed(format!(
                    "Unexpected response: {}",
                    response.status
                )));
            }
        }
    }
}

/// Create stored tokens from a token response.
fn create_stored_tokens(grpc_url: &str, token: TokenResponse) -> StoredTokens {
    let expires_at = token
        .expires_in
        .map(|ttl| chrono::Utc::now().timestamp() + ttl);

    StoredTokens {
        server: grpc_url.to_string(),
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        token_type: token.token_type,
        expires_at,
    }
}

/// Check if a token is expired.
fn is_token_expired(tokens: &StoredTokens) -> bool {
    tokens
        .expires_at
        .map(|exp| chrono::Utc::now().timestamp() >= exp)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_device_name() {
        let name = get_device_name();
        assert!(name.starts_with("mic@"));
        assert!(name.len() > 4); // "mic@" + at least 1 char
    }

    #[test]
    fn test_is_token_expired() {
        let now = chrono::Utc::now().timestamp();
        
        // Not expired
        let tokens = StoredTokens {
            server: "test".into(),
            access_token: "token".into(),
            refresh_token: None,
            token_type: "Bearer".into(),
            expires_at: Some(now + 3600),
        };
        assert!(!is_token_expired(&tokens));

        // Expired
        let expired = StoredTokens {
            expires_at: Some(now - 100),
            ..tokens.clone()
        };
        assert!(is_token_expired(&expired));

        // No expiry
        let no_expiry = StoredTokens {
            expires_at: None,
            ..tokens
        };
        assert!(!is_token_expired(&no_expiry));
    }

    #[test]
    fn test_resolve_client_id() {
        let server_with_id = config::ServerConfig {
            client_id: Some("custom-id".into()),
            ..Default::default()
        };
        assert_eq!(
            resolve_client_id(&server_with_id, "https://example.com"),
            Some("custom-id".into())
        );

        let server_no_id = config::ServerConfig::default();
        assert_eq!(
            resolve_client_id(&server_no_id, "https://micelio.dev"),
            Some(FIRST_PARTY_CLIENT_ID.into())
        );
        assert_eq!(
            resolve_client_id(&server_no_id, "https://example.com"),
            None
        );
    }
}
