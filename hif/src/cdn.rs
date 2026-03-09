//! CDN blob fetching support.
//!
#![allow(dead_code)]

//! Blobs can be fetched from a CDN for better performance,
//! falling back to gRPC if the CDN is unavailable.

use crate::config::Config;
use crate::error::{MicError, Result};
use crate::http_client;

/// Options for fetching blobs.
#[derive(Debug, Clone, Default)]
pub struct BlobFetchOptions {
    /// CDN base URL
    pub cdn_base_url: Option<String>,
    /// Repository ID (for CDN path construction)
    pub repository_id: Option<String>,
    /// Access token
    pub access_token: Option<String>,
}

impl BlobFetchOptions {
    /// Create options from server configuration.
    pub fn from_config(server: &str, access_token: Option<&str>) -> Self {
        let mut options = Self {
            access_token: access_token.map(String::from),
            ..Default::default()
        };

        if let Ok(config) = Config::load() {
            if let Some(server_config) = config.find_server_by_grpc_url(server) {
                options.cdn_base_url = server_config.cdn_url.clone();
            }
        }

        options
    }

    /// Check if CDN fetching is available.
    pub fn has_cdn(&self) -> bool {
        self.cdn_base_url.is_some() && self.repository_id.is_some()
    }
}

/// Fetch a blob, trying CDN first then falling back to gRPC.
pub async fn fetch_blob(
    server: &str,
    account: &str,
    repository: &str,
    blob_hash: &str,
    options: &BlobFetchOptions,
) -> Result<Vec<u8>> {
    // Try CDN first if available
    if let (Some(cdn_url), Some(repository_id)) = (&options.cdn_base_url, &options.repository_id) {
        match fetch_from_cdn(cdn_url, repository_id, blob_hash).await {
            Ok(content) => return Ok(content),
            Err(_) => {
                // Fall through to gRPC
            }
        }
    }

    // Fall back to gRPC
    fetch_from_grpc(server, account, repository, blob_hash).await
}

/// Fetch a blob from the CDN.
async fn fetch_from_cdn(
    cdn_base_url: &str,
    repository_id: &str,
    blob_hash: &str,
) -> Result<Vec<u8>> {
    let url = cdn_url_for_blob(cdn_base_url, repository_id, blob_hash);

    let client = http_client::create_client();
    let response = http_client::get(&client, &url).await?;

    if response.status.is_success() {
        Ok(response.body.into_bytes())
    } else {
        Err(MicError::Other(format!(
            "CDN fetch failed: {}",
            response.status
        )))
    }
}

/// Fetch a blob via gRPC.
async fn fetch_from_grpc(
    server: &str,
    _account: &str,
    _repository: &str,
    blob_hash: &str,
) -> Result<Vec<u8>> {
    use crate::grpc::hif_v1::{call, pb};
    use crate::grpc::{Endpoint, GrpcClient};

    let endpoint = Endpoint::parse(server)?;
    let client = GrpcClient::new(endpoint);
    let content_hash = hex_decode(blob_hash).ok_or_else(|| {
        MicError::Other(format!(
            "Invalid blob hash '{}': expected lowercase hex string",
            blob_hash
        ))
    })?;

    let response: pb::BlobResponse = call(
        &client,
        "/hif.v1.ContentService/GetBlob",
        &pb::GetBlobRequest { content_hash },
    )
    .await?;

    Ok(response.content)
}

/// Build the CDN URL for a blob.
fn cdn_url_for_blob(cdn_base_url: &str, repository_id: &str, blob_hash: &str) -> String {
    let base = cdn_base_url.trim_end_matches('/');
    let prefix = &blob_hash[..2.min(blob_hash.len())];
    format!(
        "{}/repositories/{}/blobs/{}/{}.bin",
        base, repository_id, prefix, blob_hash
    )
}

/// Encode bytes as lowercase hex.
pub fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Decode hex string to bytes.
pub fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    if hex.len() % 2 != 0 {
        return None;
    }

    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cdn_url_construction() {
        let url = cdn_url_for_blob("https://cdn.example.com/", "repository-123", "aabbccdd");
        assert_eq!(
            url,
            "https://cdn.example.com/repositories/repository-123/blobs/aa/aabbccdd.bin"
        );
    }

    #[test]
    fn cdn_url_without_trailing_slash() {
        let url = cdn_url_for_blob("https://cdn.example.com", "repository-123", "aabbccdd");
        assert_eq!(
            url,
            "https://cdn.example.com/repositories/repository-123/blobs/aa/aabbccdd.bin"
        );
    }

    #[test]
    fn hex_encode_decode_roundtrip() {
        let bytes = vec![0xaa, 0xbb, 0xcc, 0xdd];
        let hex = hex_encode(&bytes);
        assert_eq!(hex, "aabbccdd");

        let decoded = hex_decode(&hex).unwrap();
        assert_eq!(decoded, bytes);
    }
}
