//! gRPC endpoint parsing and configuration.
#![allow(dead_code)]

use crate::error::{MicError, Result};
use url::Url;

/// gRPC endpoint configuration.
#[derive(Debug, Clone)]
pub struct Endpoint {
    /// Target address (host:port)
    pub target: String,
    /// Host name (for TLS SNI)
    pub host: String,
    /// Whether to use TLS
    pub use_tls: bool,
}

impl Endpoint {
    /// Parse a server URL into an endpoint.
    pub fn parse(server: &str) -> Result<Self> {
        let url = Url::parse(server)
            .map_err(|e| MicError::InvalidServer(format!("invalid URL: {}", e)))?;

        let scheme = url.scheme();
        if scheme.is_empty() {
            return Err(MicError::InvalidServer(
                "URL must have a scheme (http or https)".to_string(),
            ));
        }

        let host = url
            .host_str()
            .ok_or_else(|| MicError::InvalidServer("URL has no host".to_string()))?;

        if host.is_empty() {
            return Err(MicError::InvalidServer("URL host is empty".to_string()));
        }

        // Allow HTTP only for localhost (development)
        let is_https = scheme == "https";
        let is_http = scheme == "http";
        let is_localhost = host == "localhost" || host == "127.0.0.1";

        if !is_https && !(is_http && is_localhost) {
            return Err(MicError::InsecureServer);
        }

        let default_port = if is_https { 443 } else { 80 };
        let port = url.port().unwrap_or(default_port);
        let target = format!("{}:{}", host, port);

        Ok(Self {
            target,
            host: host.to_string(),
            use_tls: is_https,
        })
    }

    /// Check if the endpoint is insecure (HTTP).
    pub fn is_insecure(&self) -> bool {
        !self.use_tls
    }

    /// Get the full URL for the endpoint.
    pub fn url(&self) -> String {
        let scheme = if self.use_tls { "https" } else { "http" };
        format!("{}://{}", scheme, self.target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_https_url() {
        let endpoint = Endpoint::parse("https://api.micelio.dev:443").unwrap();
        assert_eq!(endpoint.host, "api.micelio.dev");
        assert_eq!(endpoint.target, "api.micelio.dev:443");
        assert!(endpoint.use_tls);
    }

    #[test]
    fn parse_https_url_default_port() {
        let endpoint = Endpoint::parse("https://api.micelio.dev").unwrap();
        assert_eq!(endpoint.target, "api.micelio.dev:443");
        assert!(endpoint.use_tls);
    }

    #[test]
    fn parse_localhost_http() {
        let endpoint = Endpoint::parse("http://localhost:50051").unwrap();
        assert_eq!(endpoint.host, "localhost");
        assert_eq!(endpoint.target, "localhost:50051");
        assert!(!endpoint.use_tls);
    }

    #[test]
    fn parse_127_0_0_1_http() {
        let endpoint = Endpoint::parse("http://127.0.0.1:50051").unwrap();
        assert_eq!(endpoint.host, "127.0.0.1");
        assert!(!endpoint.use_tls);
    }

    #[test]
    fn parse_http_non_localhost_fails() {
        let result = Endpoint::parse("http://example.com:50051");
        assert!(matches!(result, Err(MicError::InsecureServer)));
    }

    #[test]
    fn parse_invalid_url() {
        let result = Endpoint::parse("not-a-url");
        assert!(matches!(result, Err(MicError::InvalidServer(_))));
    }

    #[test]
    fn endpoint_url() {
        let endpoint = Endpoint::parse("https://api.micelio.dev:443").unwrap();
        assert_eq!(endpoint.url(), "https://api.micelio.dev:443");

        let localhost = Endpoint::parse("http://localhost:50051").unwrap();
        assert_eq!(localhost.url(), "http://localhost:50051");
    }
}
