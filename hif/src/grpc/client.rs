//! gRPC client for Micelio forge communication.
//!
//! This module provides a simplified gRPC client that uses HTTP/2 POST requests
//! with protobuf encoding. Since we're not using code generation, we handle
//! the protobuf encoding/decoding manually.
#![allow(dead_code)]

use crate::error::{MicError, Result};
use crate::grpc::retry::{is_retryable_error, retry};
use crate::grpc::{Endpoint, RetryConfig};
use reqwest::header::{HeaderMap, HeaderValue, CONTENT_TYPE};
use std::time::Duration;

/// gRPC client for Micelio services.
#[derive(Clone)]
pub struct GrpcClient {
    client: reqwest::Client,
    endpoint: Endpoint,
    retry_config: RetryConfig,
}

impl GrpcClient {
    /// Create a new gRPC client for the given endpoint.
    pub fn new(endpoint: Endpoint) -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .pool_idle_timeout(Duration::from_secs(90))
            .build()
            .unwrap_or_else(|_| reqwest::Client::new());

        Self {
            client,
            endpoint,
            retry_config: RetryConfig::default(),
        }
    }

    /// Create a client with custom retry configuration.
    pub fn with_retry(mut self, config: RetryConfig) -> Self {
        self.retry_config = config;
        self
    }

    /// Perform a unary gRPC call.
    ///
    /// # Arguments
    /// - `method`: Full method path (e.g., "/micelio.auth.v1.AuthService/Login")
    /// - `request`: Protobuf-encoded request bytes
    /// - `auth_token`: Optional authentication token
    ///
    /// # Returns
    /// The protobuf-encoded response bytes.
    pub async fn unary_call(
        &self,
        method: &str,
        request: &[u8],
        auth_token: Option<&str>,
    ) -> Result<Vec<u8>> {
        let url = format!("{}{}", self.endpoint.url(), method);
        let rpc_method = method.to_string();
        let request = request.to_vec();
        let auth_token = auth_token.map(|s| s.to_string());

        let client = self.client.clone();
        let retry_config = self.retry_config.clone();

        retry(&retry_config, || {
            let url = url.clone();
            let request = request.clone();
            let auth_token = auth_token.clone();
            let client = client.clone();
            let rpc_method = rpc_method.clone();

            async move {
                Self::do_unary_call(&client, &url, &rpc_method, &request, auth_token.as_deref())
                    .await
            }
        })
        .await
    }

    /// Perform a unary gRPC call using the current stored auth token.
    ///
    /// Token lookup and refresh are resolved at call time.
    pub async fn unary_call_authed(&self, method: &str, request: &[u8]) -> Result<Vec<u8>> {
        let tokens = crate::config::require_tokens()?;
        self.unary_call(method, request, Some(&tokens.access_token))
            .await
    }

    /// Internal unary call implementation.
    async fn do_unary_call(
        client: &reqwest::Client,
        url: &str,
        rpc_method: &str,
        request: &[u8],
        auth_token: Option<&str>,
    ) -> Result<Vec<u8>> {
        let mut headers = HeaderMap::new();
        headers.insert(
            CONTENT_TYPE,
            HeaderValue::from_static("application/grpc+proto"),
        );
        headers.insert("grpc-accept-encoding", HeaderValue::from_static("identity"));
        headers.insert("te", HeaderValue::from_static("trailers"));

        if let Some(token) = auth_token {
            headers.insert(
                "authorization",
                HeaderValue::from_str(&format!("Bearer {}", token))
                    .unwrap_or_else(|_| HeaderValue::from_static("")),
            );
        }

        // gRPC message format: 1 byte compression flag + 4 bytes length + payload
        let mut body = Vec::with_capacity(5 + request.len());
        body.push(0); // No compression
        body.extend_from_slice(&(request.len() as u32).to_be_bytes());
        body.extend_from_slice(request);

        let started_at = crate::diagnostics::timestamp_now();
        let started = std::time::Instant::now();
        let request_headers = crate::diagnostics::header_pairs(&headers);
        let request_body = crate::diagnostics::capture_binary_body(&body, "application/grpc+proto");
        let request_body_bytes = body.clone();

        let resp = match client
            .post(url)
            .headers(headers)
            .body(body.clone())
            .send()
            .await
        {
            Ok(response) => response,
            Err(error) => {
                crate::diagnostics::record_network_exchange(crate::diagnostics::NetworkExchange {
                    kind: "grpc",
                    started_at: started_at.clone(),
                    duration: started.elapsed(),
                    method: "POST".to_string(),
                    url: url.to_string(),
                    http_version: None,
                    request_headers: request_headers.clone(),
                    request_body: Some(request_body.clone()),
                    response_status: 0,
                    response_status_text: "request failed".to_string(),
                    response_headers: Vec::new(),
                    response_body: None,
                    error: Some(error.to_string()),
                });
                crate::diagnostics::record_grpc_exchange(crate::diagnostics::GrpcExchange {
                    started_at: crate::diagnostics::timestamp_now(),
                    duration: started.elapsed(),
                    method: rpc_method.to_string(),
                    url: url.to_string(),
                    http_version: None,
                    http_status: 0,
                    request_headers: request_headers.clone(),
                    response_headers: Vec::new(),
                    grpc_status: None,
                    grpc_message: None,
                    request_body: request_body_bytes.clone(),
                    response_body: None,
                    error: Some(error.to_string()),
                });
                return Err(error.into());
            }
        };

        let status = resp.status();
        let http_version = crate::diagnostics::http_version_label(resp.version());
        let response_headers = crate::diagnostics::header_pairs(resp.headers());
        let grpc_status = resp
            .headers()
            .get("grpc-status")
            .and_then(|value| value.to_str().ok())
            .map(str::trim)
            .map(str::to_string);
        let grpc_message = resp
            .headers()
            .get("grpc-message")
            .and_then(|value| value.to_str().ok())
            .map(str::trim)
            .map(str::to_string);

        let response_body = match resp.bytes().await {
            Ok(body) => body,
            Err(error) => {
                crate::diagnostics::record_network_exchange(crate::diagnostics::NetworkExchange {
                    kind: "grpc",
                    started_at: started_at.clone(),
                    duration: started.elapsed(),
                    method: "POST".to_string(),
                    url: url.to_string(),
                    http_version: Some(http_version.clone()),
                    request_headers: request_headers.clone(),
                    request_body: Some(request_body.clone()),
                    response_status: status.as_u16(),
                    response_status_text: status
                        .canonical_reason()
                        .unwrap_or("gRPC response")
                        .to_string(),
                    response_headers: response_headers.clone(),
                    response_body: None,
                    error: Some(error.to_string()),
                });
                crate::diagnostics::record_grpc_exchange(crate::diagnostics::GrpcExchange {
                    started_at: started_at.clone(),
                    duration: started.elapsed(),
                    method: rpc_method.to_string(),
                    url: url.to_string(),
                    http_version: Some(http_version),
                    http_status: status.as_u16(),
                    request_headers: request_headers.clone(),
                    response_headers: response_headers.clone(),
                    grpc_status: grpc_status.clone(),
                    grpc_message: grpc_message.clone(),
                    request_body: request_body_bytes.clone(),
                    response_body: None,
                    error: Some(error.to_string()),
                });
                return Err(error.into());
            }
        };
        let captured_response_body =
            crate::diagnostics::capture_binary_body(&response_body, "application/grpc+proto");

        crate::diagnostics::record_network_exchange(crate::diagnostics::NetworkExchange {
            kind: "grpc",
            started_at: started_at.clone(),
            duration: started.elapsed(),
            method: "POST".to_string(),
            url: url.to_string(),
            http_version: Some(http_version.clone()),
            request_headers: request_headers.clone(),
            request_body: Some(request_body),
            response_status: status.as_u16(),
            response_status_text: status
                .canonical_reason()
                .unwrap_or("gRPC response")
                .to_string(),
            response_headers: response_headers.clone(),
            response_body: Some(captured_response_body),
            error: None,
        });
        crate::diagnostics::record_grpc_exchange(crate::diagnostics::GrpcExchange {
            started_at: started_at.clone(),
            duration: started.elapsed(),
            method: rpc_method.to_string(),
            url: url.to_string(),
            http_version: Some(http_version),
            http_status: status.as_u16(),
            request_headers,
            response_headers,
            grpc_status: grpc_status.clone(),
            grpc_message: grpc_message.clone(),
            request_body: request_body_bytes,
            response_body: Some(response_body.to_vec()),
            error: None,
        });

        // Check if we should retry
        if is_retryable_error(status) {
            return Err(MicError::GrpcError(format!("Retryable error: {}", status)));
        }

        if let Some(code) = grpc_status.as_deref() {
            if code != "0" {
                let message = grpc_message
                    .filter(|value| !value.is_empty())
                    .unwrap_or_else(|| format!("gRPC call failed with grpc-status {}", code));
                return Err(MicError::GrpcError(message));
            }
        }

        // Check HTTP status when no explicit gRPC status is available.
        if !status.is_success() {
            let error_msg = if response_body.len() > 5 {
                // Try to extract error message from response
                String::from_utf8_lossy(&response_body[5..]).to_string()
            } else {
                format!("gRPC call failed with status {}", status)
            };
            return Err(MicError::GrpcError(error_msg));
        }

        // Parse gRPC response: 1 byte compression flag + 4 bytes length + payload.
        // A valid unary response must include at least one message frame header.
        if response_body.len() < 5 {
            return Err(MicError::GrpcError(
                "gRPC call returned no message frame. \
                 The server may have returned a trailer-only error (grpc-status)."
                    .to_string(),
            ));
        }
        let compressed = response_body[0];
        if compressed != 0 {
            return Err(MicError::GrpcError(format!(
                "Unsupported gRPC compression flag: {}",
                compressed
            )));
        }
        let message_len = u32::from_be_bytes([
            response_body[1],
            response_body[2],
            response_body[3],
            response_body[4],
        ]) as usize;

        if response_body.len() < 5 + message_len {
            return Err(MicError::GrpcError(format!(
                "Malformed gRPC frame: declared length {} but body has {} bytes",
                message_len,
                response_body.len().saturating_sub(5)
            )));
        }

        Ok(response_body[5..5 + message_len].to_vec())
    }

    /// Perform a unary gRPC call and return a result with error details.
    pub async fn unary_call_result(
        &self,
        method: &str,
        request: &[u8],
        auth_token: Option<&str>,
    ) -> GrpcResult {
        match self.unary_call(method, request, auth_token).await {
            Ok(bytes) => GrpcResult::Ok(bytes),
            Err(MicError::GrpcError(msg)) => GrpcResult::Err(msg),
            Err(e) => GrpcResult::Err(e.to_string()),
        }
    }

    /// Get the endpoint.
    pub fn endpoint(&self) -> &Endpoint {
        &self.endpoint
    }
}

/// Result of a gRPC call.
pub enum GrpcResult {
    /// Successful response with protobuf bytes.
    Ok(Vec<u8>),
    /// Error with message.
    Err(String),
}

impl GrpcResult {
    /// Check if the result is successful.
    pub fn is_ok(&self) -> bool {
        matches!(self, GrpcResult::Ok(_))
    }

    /// Check if the result is an error.
    pub fn is_err(&self) -> bool {
        matches!(self, GrpcResult::Err(_))
    }

    /// Get the response bytes if successful.
    pub fn ok(self) -> Option<Vec<u8>> {
        match self {
            GrpcResult::Ok(bytes) => Some(bytes),
            GrpcResult::Err(_) => None,
        }
    }

    /// Get the error message if failed.
    pub fn err(self) -> Option<String> {
        match self {
            GrpcResult::Ok(_) => None,
            GrpcResult::Err(msg) => Some(msg),
        }
    }
}

// ============================================================================
// Simple Protobuf Encoding/Decoding Helpers
// ============================================================================

/// Write a varint to a buffer.
pub fn write_varint(buf: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        buf.push((value as u8 & 0x7f) | 0x80);
        value >>= 7;
    }
    buf.push(value as u8);
}

/// Read a varint from a buffer.
pub fn read_varint(data: &[u8], pos: &mut usize) -> Option<u64> {
    let mut value: u64 = 0;
    let mut shift = 0;

    while *pos < data.len() {
        let byte = data[*pos];
        *pos += 1;

        value |= ((byte & 0x7f) as u64) << shift;

        if (byte & 0x80) == 0 {
            return Some(value);
        }

        shift += 7;
        if shift >= 64 {
            return None;
        }
    }

    None
}

/// Write a length-delimited field (string or bytes).
pub fn write_length_delimited(buf: &mut Vec<u8>, field_number: u32, data: &[u8]) {
    let tag = (field_number << 3) | 2; // Wire type 2 = length-delimited
    write_varint(buf, tag as u64);
    write_varint(buf, data.len() as u64);
    buf.extend_from_slice(data);
}

/// Write a varint field.
pub fn write_varint_field(buf: &mut Vec<u8>, field_number: u32, value: u64) {
    let tag = (field_number << 3) | 0; // Wire type 0 = varint
    write_varint(buf, tag as u64);
    write_varint(buf, value);
}

/// Read a field from protobuf data.
/// Returns (field_number, wire_type, field_data).
pub fn read_field<'a>(data: &'a [u8], pos: &mut usize) -> Option<(u32, u8, &'a [u8])> {
    let tag = read_varint(data, pos)? as u32;
    let field_number = tag >> 3;
    let wire_type = (tag & 0x7) as u8;

    let field_data = match wire_type {
        0 => {
            // Varint
            let start = *pos;
            let _ = read_varint(data, pos)?;
            &data[start..*pos]
        }
        1 => {
            // 64-bit
            if *pos + 8 > data.len() {
                return None;
            }
            let result = &data[*pos..*pos + 8];
            *pos += 8;
            result
        }
        2 => {
            // Length-delimited
            let len = read_varint(data, pos)? as usize;
            if *pos + len > data.len() {
                return None;
            }
            let result = &data[*pos..*pos + len];
            *pos += len;
            result
        }
        5 => {
            // 32-bit
            if *pos + 4 > data.len() {
                return None;
            }
            let result = &data[*pos..*pos + 4];
            *pos += 4;
            result
        }
        _ => return None,
    };

    Some((field_number, wire_type, field_data))
}

/// Read a string field from field data.
pub fn read_string(data: &[u8]) -> String {
    String::from_utf8_lossy(data).to_string()
}

/// Read a varint from field data.
pub fn read_varint_value(data: &[u8]) -> u64 {
    let mut pos = 0;
    read_varint(data, &mut pos).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_write_read_varint() {
        let mut buf = Vec::new();
        write_varint(&mut buf, 300);

        let mut pos = 0;
        let value = read_varint(&buf, &mut pos).unwrap();
        assert_eq!(value, 300);
    }

    #[test]
    fn test_write_read_length_delimited() {
        let mut buf = Vec::new();
        write_length_delimited(&mut buf, 1, b"hello");

        let mut pos = 0;
        let (field_number, wire_type, data) = read_field(&buf, &mut pos).unwrap();
        assert_eq!(field_number, 1);
        assert_eq!(wire_type, 2);
        assert_eq!(data, b"hello");
    }
}
