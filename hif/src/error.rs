//! Error types for the hif CLI.
//!
//! This module provides a unified error type with error codes for JSON output
//! and human-readable messages for terminal output.

use thiserror::Error;

/// The main error type for hif operations.
#[derive(Error, Debug)]
pub enum MicError {
    // =========================================================================
    // Authentication errors
    // =========================================================================
    #[error("Not authenticated. Run 'hif auth login' first.")]
    NotAuthenticated,

    #[error("Access token expired. Run 'hif auth login' again.")]
    TokenExpired,

    #[error("Invalid stored token data. Run 'hif auth login' again.")]
    InvalidTokens,

    #[error("Device code expired during authorization")]
    DeviceCodeExpired,

    #[error("Authorization failed: {0}")]
    AuthorizationFailed(String),

    #[error("Token refresh failed: {0}")]
    RefreshFailed(String),

    // =========================================================================
    // Configuration errors
    // =========================================================================
    #[error("No default server configured. Add one with 'hif config set-server'.")]
    NoDefaultServer,

    #[error("Server configuration missing web_url")]
    NoWebUrl,

    #[error("Server configuration missing grpc_url")]
    NoGrpcUrl,

    #[error("Server discovery failed: {0}")]
    DiscoveryFailed(String),

    #[error("Invalid server URL: {0}")]
    InvalidServer(String),

    #[error("gRPC requires HTTPS (HTTP allowed only for localhost)")]
    InsecureServer,

    #[error("Configuration error: {0}")]
    ConfigError(String),

    // =========================================================================
    // Session errors
    // =========================================================================
    #[error("Session already active. Run 'hif session status' to see it or 'hif session abandon' to discard it.")]
    SessionAlreadyActive,

    #[error("No active session. Start one with 'hif session start'.")]
    NoActiveSession,

    #[error("Conflicts detected during landing")]
    ConflictsDetected,

    // =========================================================================
    // Workspace errors
    // =========================================================================
    #[error("No workspace found. Run 'hif checkout' or 'hif link' first.")]
    NoWorkspace,

    #[error("{0}")]
    NotInWorkspace(String),

    #[error("Invalid path: {0}")]
    InvalidPath(String),

    #[error("{0}")]
    InvalidRepositoryRef(String),

    /// Path not found in repository.
    #[allow(dead_code)]
    #[error("Path not found: {0}")]
    PathNotFound(String),

    // =========================================================================
    // Network errors
    // =========================================================================
    #[error("gRPC error: {0}")]
    GrpcError(String),

    /// HTTP error (for non-reqwest errors).
    #[allow(dead_code)]
    #[error("HTTP error: {0}")]
    HttpError(String),

    #[error("No diagnostics session found. Run a hif command first.")]
    NoDiagnosticsSession,

    #[error("Diagnostics session not found: {0}")]
    DiagnosticsSessionNotFound(String),

    // =========================================================================
    // Wrapped errors
    // =========================================================================
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("HTTP client error: {0}")]
    Reqwest(#[from] reqwest::Error),

    // =========================================================================
    // Generic errors
    // =========================================================================
    #[error("{0}")]
    Other(String),
}

impl MicError {
    /// Get the error code for JSON output and programmatic handling.
    pub fn code(&self) -> &'static str {
        match self {
            // Auth
            MicError::NotAuthenticated => "not_authenticated",
            MicError::TokenExpired => "token_expired",
            MicError::InvalidTokens => "invalid_tokens",
            MicError::DeviceCodeExpired => "device_code_expired",
            MicError::AuthorizationFailed(_) => "authorization_failed",
            MicError::RefreshFailed(_) => "refresh_failed",

            // Config
            MicError::NoDefaultServer => "no_default_server",
            MicError::NoWebUrl => "no_web_url",
            MicError::NoGrpcUrl => "no_grpc_url",
            MicError::DiscoveryFailed(_) => "discovery_failed",
            MicError::InvalidServer(_) => "invalid_server",
            MicError::InsecureServer => "insecure_server",
            MicError::ConfigError(_) => "config_error",

            // Session
            MicError::SessionAlreadyActive => "session_already_active",
            MicError::NoActiveSession => "no_active_session",
            MicError::ConflictsDetected => "conflicts_detected",

            // Workspace
            MicError::NoWorkspace => "no_workspace",
            MicError::NotInWorkspace(_) => "not_in_workspace",
            MicError::InvalidPath(_) => "invalid_path",
            MicError::InvalidRepositoryRef(_) => "invalid_repository_ref",
            MicError::PathNotFound(_) => "path_not_found",

            // Network
            MicError::GrpcError(_) => "grpc_error",
            MicError::HttpError(_) => "http_error",
            MicError::NoDiagnosticsSession => "no_diagnostics_session",
            MicError::DiagnosticsSessionNotFound(_) => "diagnostics_session_not_found",

            // Wrapped
            MicError::Io(_) => "io_error",
            MicError::Json(_) => "json_error",
            MicError::Reqwest(_) => "http_error",

            // Generic
            MicError::Other(_) => "error",
        }
    }

    /// Check if this error is retryable.
    #[allow(dead_code)]
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            MicError::GrpcError(_) | MicError::HttpError(_) | MicError::Reqwest(_)
        )
    }
}

/// Result type alias for hif operations.
pub type Result<T> = std::result::Result<T, MicError>;

/// Extension trait for adding context to errors.
#[allow(dead_code)]
pub trait ResultExt<T> {
    /// Add context to an error.
    fn context(self, msg: &str) -> Result<T>;

    /// Add context with a closure (lazy evaluation).
    fn with_context<F: FnOnce() -> String>(self, f: F) -> Result<T>;
}

impl<T, E: std::error::Error> ResultExt<T> for std::result::Result<T, E> {
    fn context(self, msg: &str) -> Result<T> {
        self.map_err(|e| MicError::Other(format!("{}: {}", msg, e)))
    }

    fn with_context<F: FnOnce() -> String>(self, f: F) -> Result<T> {
        self.map_err(|e| MicError::Other(format!("{}: {}", f(), e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_codes_are_valid_identifiers() {
        // All error codes should be valid snake_case identifiers
        let errors = [
            MicError::NotAuthenticated,
            MicError::TokenExpired,
            MicError::InvalidTokens,
            MicError::NoDefaultServer,
            MicError::NoWorkspace,
            MicError::InvalidRepositoryRef("test".into()),
            MicError::ConfigError("test".into()),
            MicError::GrpcError("test".into()),
            MicError::DiscoveryFailed("test".into()),
        ];

        for error in errors {
            let code = error.code();
            assert!(!code.is_empty(), "Error code should not be empty");
            assert!(
                code.chars().all(|c| c.is_ascii_lowercase() || c == '_'),
                "Error code '{}' should be snake_case",
                code
            );
        }
    }

    #[test]
    fn is_retryable() {
        assert!(MicError::GrpcError("timeout".into()).is_retryable());
        assert!(MicError::HttpError("503".into()).is_retryable());
        assert!(!MicError::NotAuthenticated.is_retryable());
        assert!(!MicError::InvalidRepositoryRef("test".into()).is_retryable());
    }

    #[test]
    fn context_extension() {
        let result: std::result::Result<(), std::io::Error> = Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "file missing",
        ));

        let with_context = result.context("Failed to read config");
        assert!(with_context.is_err());

        let err = with_context.unwrap_err();
        assert!(err.to_string().contains("Failed to read config"));
        assert!(err.to_string().contains("file missing"));
    }
}
