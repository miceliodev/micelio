//! HTTP client utilities for hif.
#![allow(dead_code)]

use crate::diagnostics::{
    self, capture_form_body, capture_json_body, capture_text_body, header_pairs, NetworkExchange,
};
use crate::error::Result;
use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use reqwest::Method;
use std::time::Instant;

/// HTTP response wrapper.
pub struct Response {
    pub status: reqwest::StatusCode,
    pub body: String,
}

/// Create a new HTTP client.
pub fn create_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new())
}

/// Perform a GET request.
pub async fn get(client: &reqwest::Client, url: &str) -> Result<Response> {
    send_request(client, Method::GET, url, HeaderMap::new(), None).await
}

/// Perform a POST request with JSON body.
pub async fn post_json(
    client: &reqwest::Client,
    url: &str,
    payload: &impl serde::Serialize,
) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    let body = serde_json::to_string(payload)?;
    send_request(
        client,
        Method::POST,
        url,
        headers,
        Some((body.clone().into_bytes(), capture_json_body(&body))),
    )
    .await
}

/// Perform a POST request with JSON body and auth token.
pub async fn post_json_auth(
    client: &reqwest::Client,
    url: &str,
    payload: &impl serde::Serialize,
    token: &str,
) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {}", token))
            .unwrap_or_else(|_| HeaderValue::from_static("")),
    );
    let body = serde_json::to_string(payload)?;
    send_request(
        client,
        Method::POST,
        url,
        headers,
        Some((body.clone().into_bytes(), capture_json_body(&body))),
    )
    .await
}

/// Perform a GET request with JSON accept and auth token.
pub async fn get_json(client: &reqwest::Client, url: &str, token: &str) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {}", token))
            .unwrap_or_else(|_| HeaderValue::from_static("")),
    );

    send_request(client, Method::GET, url, headers, None).await
}

/// Perform a POST request with form-encoded body.
pub async fn post_form(client: &reqwest::Client, url: &str, payload: &str) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_static("application/x-www-form-urlencoded"),
    );
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    send_request(
        client,
        Method::POST,
        url,
        headers,
        Some((payload.as_bytes().to_vec(), capture_form_body(payload))),
    )
    .await
}

async fn send_request(
    client: &reqwest::Client,
    method: Method,
    url: &str,
    headers: HeaderMap,
    body: Option<(Vec<u8>, diagnostics::CapturedBody)>,
) -> Result<Response> {
    let started_at = diagnostics::timestamp_now();
    let started = Instant::now();
    let request_headers = header_pairs(&headers);
    let request_body = body.as_ref().map(|(_, body)| body.clone());

    let mut request = client.request(method.clone(), url).headers(headers);
    if let Some((bytes, _)) = body {
        request = request.body(bytes);
    }

    let response = match request.send().await {
        Ok(response) => response,
        Err(error) => {
            diagnostics::record_network_exchange(NetworkExchange {
                kind: "http",
                started_at,
                duration: started.elapsed(),
                method: method.to_string(),
                url: url.to_string(),
                http_version: None,
                request_headers,
                request_body,
                response_status: 0,
                response_status_text: "request failed".to_string(),
                response_headers: Vec::new(),
                response_body: None,
                error: Some(error.to_string()),
            });
            return Err(error.into());
        }
    };
    let status = response.status();
    let version = diagnostics::http_version_label(response.version());
    let response_headers = header_pairs(response.headers());
    let content_type = response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("text/plain")
        .to_string();
    let response_body = match response.text().await {
        Ok(body) => body,
        Err(error) => {
            diagnostics::record_network_exchange(NetworkExchange {
                kind: "http",
                started_at,
                duration: started.elapsed(),
                method: method.to_string(),
                url: url.to_string(),
                http_version: Some(version),
                request_headers,
                request_body,
                response_status: status.as_u16(),
                response_status_text: status
                    .canonical_reason()
                    .unwrap_or("HTTP response")
                    .to_string(),
                response_headers,
                response_body: None,
                error: Some(error.to_string()),
            });
            return Err(error.into());
        }
    };
    let captured_response_body = capture_text_body(&response_body, &content_type);

    diagnostics::record_network_exchange(NetworkExchange {
        kind: "http",
        started_at,
        duration: started.elapsed(),
        method: method.to_string(),
        url: url.to_string(),
        http_version: Some(version),
        request_headers,
        request_body,
        response_status: status.as_u16(),
        response_status_text: status
            .canonical_reason()
            .unwrap_or("HTTP response")
            .to_string(),
        response_headers,
        response_body: Some(captured_response_body),
        error: None,
    });

    Ok(Response {
        status,
        body: response_body,
    })
}
