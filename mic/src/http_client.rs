//! HTTP client utilities for mic.
#![allow(dead_code)]

use crate::error::Result;
use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, CONTENT_TYPE};

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
    let resp = client.get(url).send().await?;

    Ok(Response {
        status: resp.status(),
        body: resp.text().await?,
    })
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

    let resp = client
        .post(url)
        .headers(headers)
        .json(payload)
        .send()
        .await?;

    Ok(Response {
        status: resp.status(),
        body: resp.text().await?,
    })
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

    let resp = client
        .post(url)
        .headers(headers)
        .json(payload)
        .send()
        .await?;

    Ok(Response {
        status: resp.status(),
        body: resp.text().await?,
    })
}

/// Perform a GET request with JSON accept and auth token.
pub async fn get_json(
    client: &reqwest::Client,
    url: &str,
    token: &str,
) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {}", token))
            .unwrap_or_else(|_| HeaderValue::from_static("")),
    );

    let resp = client.get(url).headers(headers).send().await?;

    Ok(Response {
        status: resp.status(),
        body: resp.text().await?,
    })
}

/// Perform a POST request with form-encoded body.
pub async fn post_form(
    client: &reqwest::Client,
    url: &str,
    payload: &str,
) -> Result<Response> {
    let mut headers = HeaderMap::new();
    headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_static("application/x-www-form-urlencoded"),
    );
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));

    let resp = client
        .post(url)
        .headers(headers)
        .body(payload.to_string())
        .send()
        .await?;

    Ok(Response {
        status: resp.status(),
        body: resp.text().await?,
    })
}
