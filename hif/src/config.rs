//! Local configuration management for hif.
//!
//! Configuration is stored in `~/.hif/config.json` (or `$HIF_HOME/config.json`
//! if the environment variable is set).
//!
//! # Configuration Structure
//!
//! ```json
//! {
//!   "default_server": "micelio.dev",
//!   "servers": {
//!     "micelio.dev": {
//!       "grpc_url": "https://api.micelio.dev:443",
//!       "web_url": "https://micelio.dev"
//!     }
//!   },
//!   "aliases": {
//!     "mp": "myorg/myrepository"
//!   }
//! }
//! ```

use crate::constants::{is_first_party_url, FIRST_PARTY_CLIENT_ID, TOKEN_REFRESH_BUFFER_SECS};
use crate::error::{MicError, Result};
#[cfg(test)]
use base64::Engine;
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::future::Future;
use std::io::{ErrorKind, Write};
use std::path::Path;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::thread;
use std::time::{Duration, Instant};

// =============================================================================
// CLI Overrides (--server / --token flags)
// =============================================================================

static SERVER_OVERRIDE: OnceLock<String> = OnceLock::new();
static TOKEN_OVERRIDE: OnceLock<String> = OnceLock::new();

/// Set the gRPC server URL override (from --server flag).
pub fn set_server_override(url: String) {
    let _ = SERVER_OVERRIDE.set(url);
}

/// Set the bearer token override (from --token flag).
pub fn set_token_override(token: String) {
    let _ = TOKEN_OVERRIDE.set(token);
}

/// Get the gRPC server URL override, if set.
pub fn server_override() -> Option<&'static str> {
    SERVER_OVERRIDE.get().map(|s| s.as_str())
}

/// Get the bearer token override, if set.
pub fn token_override() -> Option<&'static str> {
    TOKEN_OVERRIDE.get().map(|s| s.as_str())
}

// =============================================================================
// Configuration Types
// =============================================================================

/// Configuration for hif CLI.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Config {
    /// Default server name (e.g., "micelio.dev", "localhost").
    pub default_server: Option<String>,

    /// Server configurations by name.
    #[serde(default)]
    pub servers: HashMap<String, ServerConfig>,

    /// Repository aliases (short name -> account/repository).
    #[serde(default)]
    pub aliases: HashMap<String, String>,

    /// User preferences.
    #[serde(default)]
    pub preferences: Preferences,
}

/// Server configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerConfig {
    /// gRPC API URL.
    pub grpc_url: Option<String>,
    /// Web UI URL.
    pub web_url: Option<String>,
    /// CDN URL for blob fetching.
    pub cdn_url: Option<String>,
    /// OAuth client ID.
    pub client_id: Option<String>,
    /// OAuth client secret (optional).
    pub client_secret: Option<String>,
}

/// Well-known discovery document.
#[derive(Debug, Deserialize)]
struct DiscoveryDocument {
    grpc_url: Option<String>,
    web_url: Option<String>,
    cdn_url: Option<String>,
    client_id: Option<String>,
}

/// Output format preference.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    #[default]
    Text,
    Json,
    Toon,
}

/// User preferences.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preferences {
    /// Default output format.
    #[serde(default)]
    pub output_format: OutputFormat,
    /// Enable colored output.
    #[serde(default = "default_true")]
    pub color: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            output_format: OutputFormat::Text,
            color: true,
        }
    }
}

fn default_true() -> bool {
    true
}

// =============================================================================
// Config Implementation
// =============================================================================

impl Config {
    /// Load configuration from disk, or create default if not exists.
    pub fn load() -> Result<Self> {
        let path = config_file_path()?;

        if !path.exists() {
            let mut config = Self::default();
            config.set_default_servers();
            return Ok(config);
        }

        let data = fs::read_to_string(&path)
            .map_err(|e| MicError::ConfigError(format!("Failed to read config: {}", e)))?;

        let mut config: Config = serde_json::from_str(&data)
            .map_err(|e| MicError::ConfigError(format!("Failed to parse config: {}", e)))?;

        // Ensure default servers are present
        if config.servers.is_empty() {
            config.set_default_servers();
        }

        Ok(config)
    }

    /// Save configuration to disk.
    #[allow(dead_code)]
    pub fn save(&self) -> Result<()> {
        ensure_config_dir()?;

        let path = config_file_path()?;
        let data = serde_json::to_string_pretty(self)
            .map_err(|e| MicError::ConfigError(format!("Failed to serialize config: {}", e)))?;

        fs::write(&path, data)
            .map_err(|e| MicError::ConfigError(format!("Failed to write config: {}", e)))?;

        Ok(())
    }

    /// Get the default server URL.
    #[allow(dead_code)]
    pub fn get_default_server(&self) -> Option<&str> {
        self.default_server
            .as_ref()
            .and_then(|name| self.servers.get(name))
            .and_then(|server| server.grpc_url.as_deref())
    }

    /// Resolve the default server configuration, using discovery when needed.
    pub async fn resolve_default_server(&mut self) -> Result<(String, ServerConfig)> {
        let name = self
            .get_default_server_name()
            .ok_or(MicError::NoDefaultServer)?
            .to_string();

        let mut needs_discovery = false;
        let mut web_url = None;

        if let Some(server) = self.servers.get(&name) {
            if server.grpc_url.is_none() {
                web_url = Some(
                    server
                        .web_url
                        .as_ref()
                        .ok_or(MicError::NoWebUrl)?
                        .to_string(),
                );
                needs_discovery = true;
            }
        } else {
            return Err(MicError::NoDefaultServer);
        }

        let mut updated = false;

        if needs_discovery {
            let discovery = discover_server(web_url.as_ref().unwrap()).await?;
            let server = self
                .servers
                .get_mut(&name)
                .ok_or(MicError::NoDefaultServer)?;
            updated = apply_discovery(server, discovery);
        }

        if updated {
            self.save()?;
        }

        let server = self.servers.get(&name).ok_or(MicError::NoDefaultServer)?;

        Ok((name, server.clone()))
    }

    /// Resolve the default gRPC server URL, using discovery when needed.
    ///
    /// If `--server` was passed on the CLI, returns that URL directly
    /// without touching the config file.
    pub async fn resolve_default_grpc_url(&mut self) -> Result<String> {
        if let Some(url) = server_override() {
            return Ok(url.to_string());
        }
        let (_name, server) = self.resolve_default_server().await?;
        server.grpc_url.ok_or(MicError::NoGrpcUrl)
    }

    /// Get the default server name.
    pub fn get_default_server_name(&self) -> Option<&str> {
        self.default_server.as_deref()
    }

    /// Set the default server by name.
    #[allow(dead_code)]
    pub fn set_default_server(&mut self, name: &str) {
        self.default_server = Some(name.to_string());
    }

    /// Get server configuration by name.
    #[allow(dead_code)]
    pub fn get_server(&self, name: &str) -> Option<&ServerConfig> {
        self.servers.get(name)
    }

    /// Find a server configuration by matching grpc_url.
    pub fn find_server_by_grpc_url(&self, grpc_url: &str) -> Option<&ServerConfig> {
        self.servers
            .values()
            .find(|s| s.grpc_url.as_deref() == Some(grpc_url))
    }

    /// Add or update a server configuration.
    #[allow(dead_code)]
    pub fn set_server(&mut self, name: &str, server: ServerConfig) {
        self.servers.insert(name.to_string(), server);
    }

    /// Get a repository alias.
    #[allow(dead_code)]
    pub fn get_alias(&self, alias: &str) -> Option<&str> {
        self.aliases.get(alias).map(|s| s.as_str())
    }

    /// Set a repository alias.
    #[allow(dead_code)]
    pub fn set_alias(&mut self, alias: &str, repository_ref: &str) {
        self.aliases
            .insert(alias.to_string(), repository_ref.to_string());
    }

    /// Remove a repository alias.
    #[allow(dead_code)]
    pub fn remove_alias(&mut self, alias: &str) -> bool {
        self.aliases.remove(alias).is_some()
    }

    /// Resolve a repository reference, expanding aliases if needed.
    #[allow(dead_code)]
    pub fn resolve_repository<'a>(&'a self, ref_str: &'a str) -> &'a str {
        self.aliases
            .get(ref_str)
            .map(|s| s.as_str())
            .unwrap_or(ref_str)
    }

    /// Set up default server configurations.
    fn set_default_servers(&mut self) {
        // Production server
        self.servers.insert(
            "micelio.dev".to_string(),
            ServerConfig {
                grpc_url: Some("https://api.micelio.dev:443".to_string()),
                web_url: Some("https://micelio.dev".to_string()),
                ..Default::default()
            },
        );

        // Local development
        self.servers.insert(
            "localhost".to_string(),
            ServerConfig {
                grpc_url: Some("http://localhost:50051".to_string()),
                web_url: Some("http://localhost:4000".to_string()),
                ..Default::default()
            },
        );

        // Set default to production
        self.default_server = Some("micelio.dev".to_string());
    }
}

// =============================================================================
// Discovery
// =============================================================================

fn discovery_url_for(web_url: &str) -> String {
    let base = web_url.trim_end_matches('/');
    format!("{}/.well-known/micelio.json", base)
}

async fn discover_server(web_url: &str) -> Result<DiscoveryDocument> {
    let client = crate::http_client::create_client();
    let url = discovery_url_for(web_url);
    let response = crate::http_client::get(&client, &url).await?;

    if !response.status.is_success() {
        return Err(MicError::DiscoveryFailed(format!(
            "Discovery request to {} failed with status {}. Set grpc_url in config.json or ensure /.well-known/micelio.json is reachable.",
            url, response.status
        )));
    }

    let document: DiscoveryDocument = serde_json::from_str(&response.body).map_err(|e| {
        MicError::DiscoveryFailed(format!(
            "Invalid discovery document: {}. Set grpc_url in config.json or ensure /.well-known/micelio.json returns valid JSON.",
            e
        ))
    })?;

    if document.grpc_url.is_none() {
        return Err(MicError::DiscoveryFailed(
            "Discovery document missing grpc_url. Set grpc_url in config.json or update the server's /.well-known/micelio.json.".to_string(),
        ));
    }

    Ok(document)
}

fn apply_discovery(server: &mut ServerConfig, discovery: DiscoveryDocument) -> bool {
    let mut updated = false;

    if server.grpc_url.is_none() {
        if let Some(grpc_url) = discovery.grpc_url {
            server.grpc_url = Some(grpc_url.trim_end_matches('/').to_string());
            updated = true;
        }
    }

    if server.web_url.is_none() {
        if let Some(web_url) = discovery.web_url {
            server.web_url = Some(web_url.trim_end_matches('/').to_string());
            updated = true;
        }
    }

    if server.cdn_url.is_none() {
        if let Some(cdn_url) = discovery.cdn_url {
            server.cdn_url = Some(cdn_url.trim_end_matches('/').to_string());
            updated = true;
        }
    }

    if server.client_id.is_none() {
        if let Some(client_id) = discovery.client_id {
            server.client_id = Some(client_id);
            updated = true;
        }
    }

    updated
}

// =============================================================================
// Path Helpers
// =============================================================================

/// Get the hif configuration directory path.
pub fn config_dir() -> Result<PathBuf> {
    if let Ok(mic_home) = std::env::var("HIF_HOME") {
        if !mic_home.is_empty() {
            return Ok(PathBuf::from(mic_home));
        }
    }

    let home = dirs::home_dir()
        .ok_or_else(|| MicError::ConfigError("Could not find home directory".to_string()))?;

    Ok(home.join(".hif"))
}

/// Get the hif state directory path.
pub fn state_dir() -> Result<PathBuf> {
    if let Ok(mic_home) = std::env::var("HIF_HOME") {
        if !mic_home.is_empty() {
            return Ok(PathBuf::from(mic_home).join("state"));
        }
    }

    if let Ok(state_home) = std::env::var("XDG_STATE_HOME") {
        if !state_home.is_empty() {
            return Ok(PathBuf::from(state_home).join("hif"));
        }
    }

    let home = dirs::home_dir()
        .ok_or_else(|| MicError::ConfigError("Could not find home directory".to_string()))?;

    Ok(home.join(".local").join("state").join("hif"))
}

/// Get the full path to the config file.
pub fn config_file_path() -> Result<PathBuf> {
    Ok(config_dir()?.join("config.json"))
}

/// Ensure the config directory exists.
pub fn ensure_config_dir() -> Result<PathBuf> {
    let dir = config_dir()?;
    if !dir.exists() {
        fs::create_dir_all(&dir)
            .map_err(|e| MicError::ConfigError(format!("Failed to create config dir: {}", e)))?;
    }
    Ok(dir)
}

/// Ensure the state directory exists.
pub fn ensure_state_dir() -> Result<PathBuf> {
    let dir = state_dir()?;
    if !dir.exists() {
        fs::create_dir_all(&dir)
            .map_err(|e| MicError::ConfigError(format!("Failed to create state dir: {}", e)))?;
    }
    Ok(dir)
}

#[cfg(test)]
fn token_subject(access_token: &str) -> Option<String> {
    let payload_segment = access_token.split('.').nth(1)?;
    let mut payload = payload_segment.to_string();

    while payload.len() % 4 != 0 {
        payload.push('=');
    }

    let bytes = base64::engine::general_purpose::URL_SAFE
        .decode(payload)
        .ok()?;

    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    value.get("sub")?.as_str().map(ToString::to_string)
}

// =============================================================================
// Token Management
// =============================================================================

/// Stored authentication tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredTokens {
    /// Stable local auth session ID for refresh locking.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    /// Server gRPC URL.
    pub server: String,
    /// OAuth access token.
    pub access_token: String,
    /// OAuth refresh token (optional).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    /// Token type (usually "Bearer").
    pub token_type: String,
    /// Token expiration timestamp (Unix epoch seconds).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<i64>,
}

impl StoredTokens {
    /// Check if the token is expired.
    pub fn is_expired(&self) -> bool {
        self.expires_at
            .map(|exp| chrono::Utc::now().timestamp() >= exp)
            .unwrap_or(false)
    }

    /// Check if the token is expiring soon (within buffer period).
    pub fn is_expiring_soon(&self) -> bool {
        self.expires_at
            .map(|exp| chrono::Utc::now().timestamp() >= exp - TOKEN_REFRESH_BUFFER_SECS)
            .unwrap_or(false)
    }
}

/// Read stored tokens from disk.
pub fn read_tokens() -> Result<Option<StoredTokens>> {
    let path = tokens_file_path()?;
    read_tokens_from_path(&path)
}

/// Write stored tokens to disk.
pub fn store_tokens(tokens: &StoredTokens) -> Result<()> {
    store_tokens_with_expected_session(tokens, None)
}

/// Delete stored tokens.
pub fn delete_tokens() -> Result<()> {
    let _state_lock = acquire_token_state_lock()?;
    let path = tokens_file_path()?;

    if path.exists() {
        fs::remove_file(&path)
            .map_err(|e| MicError::ConfigError(format!("Failed to delete tokens: {}", e)))?;
    }

    Ok(())
}

/// Require valid authentication tokens, refreshing if needed.
///
/// If `--token` was passed on the CLI, returns a synthetic `StoredTokens`
/// with that token directly, skipping disk-based token management.
pub fn require_tokens() -> Result<StoredTokens> {
    if let Some(token) = token_override() {
        return Ok(StoredTokens {
            session_id: None,
            server: server_override().unwrap_or_default().to_string(),
            access_token: token.to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_at: None,
        });
    }

    let mut tokens = read_tokens()?.ok_or(MicError::NotAuthenticated)?;

    if tokens.server.is_empty() {
        return Err(MicError::InvalidTokens);
    }

    tokens = ensure_token_session(tokens)?;

    // Check if token needs refresh
    if tokens.is_expiring_soon() {
        if tokens.refresh_token.is_some() {
            let _lock = acquire_refresh_lock(&tokens)?;

            // Re-read after lock acquisition in case another process already refreshed.
            let mut latest = read_tokens()?.ok_or(MicError::NotAuthenticated)?;
            if latest.server.is_empty() {
                return Err(MicError::InvalidTokens);
            }
            latest = ensure_token_session(latest)?;

            // Another auth session replaced tokens while waiting on lock.
            if latest.session_id != tokens.session_id {
                if latest.is_expired() {
                    return Err(MicError::TokenExpired);
                }
                return Ok(latest);
            }

            if !latest.is_expiring_soon() {
                return Ok(latest);
            }

            if let Some(ref latest_refresh_token) = latest.refresh_token {
                match refresh_tokens_sync(
                    &latest.server,
                    latest_refresh_token,
                    latest.session_id.as_deref(),
                ) {
                    Ok(new_tokens) => return Ok(new_tokens),
                    Err(_) if !latest.is_expired() => {
                        if let Some(current) = read_tokens()? {
                            if current.server == latest.server
                                && !current.is_expired()
                                && current.session_id != latest.session_id
                            {
                                return Ok(current);
                            }
                        }
                        // Token not yet expired, continue with current.
                        return Ok(latest);
                    }
                    Err(_) => return Err(MicError::TokenExpired),
                }
            }

            if latest.is_expired() {
                return Err(MicError::TokenExpired);
            }

            return Ok(latest);
        }

        if tokens.is_expired() {
            return Err(MicError::TokenExpired);
        }
    }

    Ok(tokens)
}

const LOCK_WAIT: Duration = Duration::from_secs(90);
const LOCK_POLL: Duration = Duration::from_millis(100);

struct FileLockGuard {
    _path: PathBuf,
    file: File,
}

impl Drop for FileLockGuard {
    fn drop(&mut self) {
        let _ = fs2::FileExt::unlock(&self.file);
    }
}

fn ensure_token_session(mut tokens: StoredTokens) -> Result<StoredTokens> {
    let existing = tokens
        .session_id
        .as_ref()
        .map(|value| value.trim())
        .unwrap_or("");
    if !existing.is_empty() {
        return Ok(tokens);
    }

    let _state_lock = acquire_token_state_lock()?;
    let path = tokens_file_path()?;
    let latest = read_tokens_from_path(&path)?.ok_or(MicError::NotAuthenticated)?;
    if latest.server.is_empty() {
        return Err(MicError::InvalidTokens);
    }

    if normalized_session_id(latest.session_id.as_deref()).is_some() {
        return Ok(latest);
    }

    tokens = latest;
    tokens.session_id = Some(uuid::Uuid::new_v4().to_string());
    write_tokens_atomic(&path, &tokens)?;
    Ok(tokens)
}

fn refresh_lock_path(tokens: &StoredTokens) -> Result<PathBuf> {
    let session_id = normalized_session_id(tokens.session_id.as_deref());
    let Some(session_id) = session_id else {
        return Err(MicError::InvalidTokens);
    };

    let server_hash = blake3::hash(tokens.server.as_bytes()).to_hex();
    Ok(config_dir()?.join(format!(
        "refresh-{}-{}.lock",
        &server_hash[..16],
        session_id
    )))
}

fn token_state_lock_path() -> Result<PathBuf> {
    Ok(config_dir()?.join("tokens.state.lock"))
}

fn acquire_refresh_lock(tokens: &StoredTokens) -> Result<FileLockGuard> {
    let lock_path = refresh_lock_path(tokens)?;
    acquire_file_lock(&lock_path, "refresh")
}

fn acquire_token_state_lock() -> Result<FileLockGuard> {
    let lock_path = token_state_lock_path()?;
    acquire_file_lock(&lock_path, "token state")
}

fn acquire_file_lock(path: &Path, lock_name: &str) -> Result<FileLockGuard> {
    ensure_config_dir()?;
    let deadline = Instant::now() + LOCK_WAIT;
    loop {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(|error| {
                MicError::RefreshFailed(format!(
                    "Failed to open {} lock file: {}",
                    lock_name, error
                ))
            })?;

        match file.try_lock_exclusive() {
            Ok(()) => {
                return Ok(FileLockGuard {
                    _path: path.to_path_buf(),
                    file,
                });
            }
            Err(error) if error.kind() == ErrorKind::WouldBlock => {
                if Instant::now() >= deadline {
                    return Err(MicError::RefreshFailed(format!(
                        "Timed out waiting for {} lock",
                        lock_name
                    )));
                }
                thread::sleep(LOCK_POLL);
            }
            Err(error) => {
                return Err(MicError::RefreshFailed(format!(
                    "Failed to acquire {} lock: {}",
                    lock_name, error
                )));
            }
        }
    }
}

fn normalized_session_id(session_id: Option<&str>) -> Option<String> {
    session_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn tokens_file_path() -> Result<PathBuf> {
    Ok(config_dir()?.join("tokens.json"))
}

fn read_tokens_from_path(path: &Path) -> Result<Option<StoredTokens>> {
    if !path.exists() {
        return Ok(None);
    }

    let data = fs::read_to_string(path)
        .map_err(|e| MicError::ConfigError(format!("Failed to read tokens: {}", e)))?;

    let tokens: StoredTokens = serde_json::from_str(&data)
        .map_err(|e| MicError::ConfigError(format!("Failed to parse tokens: {}", e)))?;

    Ok(Some(tokens))
}

fn store_tokens_with_expected_session(
    tokens: &StoredTokens,
    expected_session_id: Option<&str>,
) -> Result<()> {
    let _state_lock = acquire_token_state_lock()?;
    let path = tokens_file_path()?;
    let expected_session_id = normalized_session_id(expected_session_id);

    if let Some(expected) = expected_session_id {
        let current_tokens = read_tokens_from_path(&path)?.ok_or(MicError::NotAuthenticated)?;
        let current_session = normalized_session_id(current_tokens.session_id.as_deref());

        if current_session.as_deref() != Some(expected.as_str()) {
            return Err(MicError::RefreshFailed(
                "Token session changed while refresh was in progress".to_string(),
            ));
        }
    }

    write_tokens_atomic(&path, tokens)
}

fn write_tokens_atomic(path: &Path, tokens: &StoredTokens) -> Result<()> {
    ensure_config_dir()?;

    let data = serde_json::to_string_pretty(tokens)
        .map_err(|e| MicError::ConfigError(format!("Failed to serialize tokens: {}", e)))?;

    let file_name = path
        .file_name()
        .ok_or_else(|| MicError::ConfigError("Invalid token file path".to_string()))?
        .to_string_lossy();
    let tmp_path = path.with_file_name(format!(
        "{}.tmp.{}.{}",
        file_name,
        std::process::id(),
        uuid::Uuid::new_v4()
    ));

    let write_result = (|| -> Result<()> {
        let mut tmp_file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp_path)
            .map_err(|e| {
                MicError::ConfigError(format!("Failed to create temp token file: {}", e))
            })?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&tmp_path, fs::Permissions::from_mode(0o600)).map_err(|e| {
                MicError::ConfigError(format!("Failed to set token permissions: {}", e))
            })?;
        }

        tmp_file
            .write_all(data.as_bytes())
            .map_err(|e| MicError::ConfigError(format!("Failed to write tokens: {}", e)))?;
        tmp_file
            .sync_all()
            .map_err(|e| MicError::ConfigError(format!("Failed to sync token file: {}", e)))?;

        fs::rename(&tmp_path, path)
            .map_err(|e| MicError::ConfigError(format!("Failed to replace tokens file: {}", e)))?;

        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }

    write_result
}

/// Refresh tokens synchronously (blocking).
fn refresh_tokens_sync(
    server: &str,
    refresh_token: &str,
    session_id: Option<&str>,
) -> Result<StoredTokens> {
    let server = server.to_string();
    let refresh_token = refresh_token.to_string();
    let session_id = session_id.map(|value| value.to_string());

    run_async_blocking(async move {
        refresh_tokens(&server, &refresh_token, session_id.as_deref()).await
    })
}

fn run_async_blocking<T, Fut>(future: Fut) -> Result<T>
where
    T: Send + 'static,
    Fut: Future<Output = Result<T>> + Send + 'static,
{
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        return match handle.runtime_flavor() {
            tokio::runtime::RuntimeFlavor::MultiThread => {
                tokio::task::block_in_place(|| handle.block_on(future))
            }
            tokio::runtime::RuntimeFlavor::CurrentThread => {
                thread::spawn(move || run_async_with_new_runtime(future))
                    .join()
                    .map_err(|_| {
                        MicError::RefreshFailed("Token refresh worker thread panicked".to_string())
                    })?
            }
            _ => thread::spawn(move || run_async_with_new_runtime(future))
                .join()
                .map_err(|_| {
                    MicError::RefreshFailed("Token refresh worker thread panicked".to_string())
                })?,
        };
    }

    run_async_with_new_runtime(future)
}

fn run_async_with_new_runtime<T, Fut>(future: Fut) -> Result<T>
where
    Fut: Future<Output = Result<T>>,
{
    let rt = tokio::runtime::Runtime::new()
        .map_err(|e| MicError::RefreshFailed(format!("Failed to create runtime: {}", e)))?;
    rt.block_on(future)
}

/// Refresh tokens using the refresh_token grant.
async fn refresh_tokens(
    grpc_url: &str,
    refresh_token: &str,
    session_id: Option<&str>,
) -> Result<StoredTokens> {
    let config = Config::load()?;

    // Find the server config by gRPC URL
    let server_config = config
        .find_server_by_grpc_url(grpc_url)
        .ok_or_else(|| MicError::ConfigError("Server not found in config".to_string()))?;

    let web_url = server_config.web_url.as_ref().ok_or(MicError::NoWebUrl)?;

    // Determine client_id
    let client_id = if let Some(ref id) = server_config.client_id {
        id.clone()
    } else if is_first_party_url(web_url) {
        FIRST_PARTY_CLIENT_ID.to_string()
    } else {
        return Err(MicError::ConfigError(
            "No client_id configured for server".to_string(),
        ));
    };

    // Build refresh token request
    let token_url = format!("{}/oauth/token", web_url);
    let payload = format!(
        "grant_type=refresh_token&refresh_token={}&client_id={}",
        urlencoding::encode(refresh_token),
        urlencoding::encode(&client_id)
    );

    let client = crate::http_client::create_client();
    let response = crate::http_client::post_form(&client, &token_url, &payload).await?;

    if response.status != reqwest::StatusCode::OK {
        return Err(MicError::RefreshFailed(format!(
            "Server returned {}",
            response.status
        )));
    }

    #[derive(serde::Deserialize)]
    struct TokenResponse {
        access_token: String,
        token_type: String,
        expires_in: Option<i64>,
        refresh_token: Option<String>,
    }

    let token: TokenResponse = serde_json::from_str(&response.body)
        .map_err(|e| MicError::RefreshFailed(format!("Invalid response: {}", e)))?;

    let expires_at = token
        .expires_in
        .map(|ttl| chrono::Utc::now().timestamp() + ttl);

    let new_tokens = StoredTokens {
        session_id: session_id.map(|value| value.to_string()),
        server: grpc_url.to_string(),
        access_token: token.access_token,
        refresh_token: token
            .refresh_token
            .or_else(|| Some(refresh_token.to_string())),
        token_type: token.token_type,
        expires_at,
    };

    // Store refreshed tokens only if this auth session is still current.
    store_tokens_with_expected_session(&new_tokens, session_id)?;

    Ok(new_tokens)
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    #[test]
    fn config_default_servers() {
        let mut config = Config::default();
        config.set_default_servers();

        assert!(config.default_server.is_some());
        assert!(config.servers.contains_key("micelio.dev"));
        assert!(config.servers.contains_key("localhost"));
    }

    #[test]
    fn config_get_default_server() {
        let mut config = Config::default();
        config.set_default_servers();

        let server_url = config.get_default_server();
        assert!(server_url.is_some());
        assert!(server_url.unwrap().contains("micelio.dev"));
    }

    #[test]
    fn config_alias_operations() {
        let mut config = Config::default();

        // Set alias
        config.set_alias("mp", "myorg/myrepository");
        assert_eq!(config.get_alias("mp"), Some("myorg/myrepository"));

        // Resolve with alias
        assert_eq!(config.resolve_repository("mp"), "myorg/myrepository");
        assert_eq!(
            config.resolve_repository("other/repository"),
            "other/repository"
        );

        // Remove alias
        assert!(config.remove_alias("mp"));
        assert!(!config.remove_alias("mp")); // Already removed
        assert_eq!(config.get_alias("mp"), None);
    }

    #[test]
    fn stored_tokens_expiry() {
        let now = chrono::Utc::now().timestamp();

        // Not expired
        let tokens = StoredTokens {
            session_id: Some("test-session".to_string()),
            server: "test".into(),
            access_token: "token".into(),
            refresh_token: None,
            token_type: "Bearer".into(),
            expires_at: Some(now + 3600),
        };
        assert!(!tokens.is_expired());
        assert!(!tokens.is_expiring_soon());

        // Expiring soon (within 5 minutes)
        let expiring_soon = StoredTokens {
            expires_at: Some(now + 60),
            ..tokens.clone()
        };
        assert!(!expiring_soon.is_expired());
        assert!(expiring_soon.is_expiring_soon());

        // Expired
        let expired = StoredTokens {
            expires_at: Some(now - 100),
            ..tokens.clone()
        };
        assert!(expired.is_expired());
        assert!(expired.is_expiring_soon());

        // No expiry
        let no_expiry = StoredTokens {
            expires_at: None,
            ..tokens
        };
        assert!(!no_expiry.is_expired());
        assert!(!no_expiry.is_expiring_soon());
    }

    #[test]
    fn discovery_url_trims_trailing_slash() {
        let url = discovery_url_for("https://micelio.example/");
        assert_eq!(url, "https://micelio.example/.well-known/micelio.json");

        let url = discovery_url_for("https://micelio.example");
        assert_eq!(url, "https://micelio.example/.well-known/micelio.json");
    }

    #[test]
    fn token_subject_extracts_sub_claim() {
        let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .encode(r#"{"sub":"user_123","aud":"micelio"}"#);
        let token = format!("header.{}.signature", payload);

        assert_eq!(token_subject(&token), Some("user_123".to_string()));
    }

    #[test]
    fn token_subject_returns_none_for_invalid_tokens() {
        assert_eq!(token_subject("not-a-jwt"), None);
        assert_eq!(token_subject("one.two"), None);
    }

    #[test]
    fn ensure_token_session_keeps_existing_session_id() {
        let tokens = StoredTokens {
            session_id: Some("session-123".to_string()),
            server: "https://api.example.com".to_string(),
            access_token: "access".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_at: Some(chrono::Utc::now().timestamp() + 3600),
        };

        let ensured = ensure_token_session(tokens.clone()).unwrap();
        assert_eq!(ensured.session_id, tokens.session_id);
    }

    #[test]
    fn refresh_lock_path_is_scoped_by_session_and_server() {
        let tokens = StoredTokens {
            session_id: Some("session-abc".to_string()),
            server: "https://api.example.com".to_string(),
            access_token: "access".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_at: Some(chrono::Utc::now().timestamp() + 3600),
        };

        let lock_path = refresh_lock_path(&tokens).unwrap();
        let filename = lock_path.file_name().unwrap().to_string_lossy();
        assert!(filename.contains("session-abc"));
        assert!(filename.starts_with("refresh-"));
        assert!(filename.ends_with(".lock"));
    }

    #[test]
    fn refresh_lock_path_rejects_missing_session_id() {
        let tokens = StoredTokens {
            session_id: None,
            server: "https://api.example.com".to_string(),
            access_token: "access".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_at: Some(chrono::Utc::now().timestamp() + 3600),
        };

        assert!(matches!(
            refresh_lock_path(&tokens),
            Err(MicError::InvalidTokens)
        ));
    }

    #[test]
    fn run_async_blocking_works_without_runtime() {
        let result = run_async_blocking(async { Ok::<_, MicError>(42) }).unwrap();
        assert_eq!(result, 42);
    }

    #[test]
    fn run_async_blocking_works_inside_multi_thread_runtime() {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .unwrap();

        let result =
            runtime.block_on(async { run_async_blocking(async { Ok::<_, MicError>(7) }).unwrap() });
        assert_eq!(result, 7);
    }

    #[test]
    fn run_async_blocking_works_inside_current_thread_runtime() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let result = runtime
            .block_on(async { run_async_blocking(async { Ok::<_, MicError>(11) }).unwrap() });
        assert_eq!(result, 11);
    }
}
