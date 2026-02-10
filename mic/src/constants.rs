//! Shared constants for the mic CLI.
//!
//! This module contains configuration constants used throughout the CLI.
//! Some constants are exported for library users but may not be used internally.

/// First-party client ID for micelio.dev OAuth.
pub const FIRST_PARTY_CLIENT_ID: &str = "ad79f0f6-8dbd-4ced-b629-567e764d2379";

/// First-party domain.
pub const FIRST_PARTY_DOMAIN: &str = "micelio.dev";

/// Default bloom filter size (expected items).
#[allow(dead_code)]
pub const BLOOM_EXPECTED_ITEMS: usize = 1000;

/// Default bloom filter false positive rate.
#[allow(dead_code)]
pub const BLOOM_FALSE_POSITIVE_RATE: f64 = 0.01;

/// Default number of hash functions for bloom filter.
#[allow(dead_code)]
pub const BLOOM_NUM_HASHES: u32 = 7;

/// Token refresh buffer in seconds (refresh 5 minutes before expiry).
pub const TOKEN_REFRESH_BUFFER_SECS: i64 = 300;

/// HTTP request timeout in seconds.
#[allow(dead_code)]
pub const HTTP_TIMEOUT_SECS: u64 = 30;

/// HTTP connect timeout in seconds.
#[allow(dead_code)]
pub const HTTP_CONNECT_TIMEOUT_SECS: u64 = 10;

/// Device code expiry default in seconds.
pub const DEVICE_CODE_EXPIRY_SECS: i64 = 900;

/// Minimum polling interval for device flow in seconds.
pub const DEVICE_POLL_MIN_INTERVAL_SECS: i64 = 1;

/// Default polling interval for device flow in seconds.
pub const DEVICE_POLL_DEFAULT_INTERVAL_SECS: i64 = 5;

/// Check if a web URL is first-party (micelio.dev).
pub fn is_first_party_url(web_url: &str) -> bool {
    if let Ok(url) = url::Url::parse(web_url) {
        if let Some(host) = url.host_str() {
            return host == FIRST_PARTY_DOMAIN 
                || host.ends_with(&format!(".{}", FIRST_PARTY_DOMAIN));
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_first_party_url() {
        assert!(is_first_party_url("https://micelio.dev"));
        assert!(is_first_party_url("https://micelio.dev/"));
        assert!(is_first_party_url("https://api.micelio.dev"));
        assert!(is_first_party_url("https://staging.micelio.dev"));
        
        assert!(!is_first_party_url("https://example.com"));
        assert!(!is_first_party_url("https://micelio.dev.evil.com"));
        assert!(!is_first_party_url("https://notmicelio.dev"));
        assert!(!is_first_party_url("invalid-url"));
    }
}
