//! Retry logic for gRPC calls.
#![allow(dead_code)]

use std::time::Duration;
use tokio::time::sleep;

/// Retry configuration.
#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Maximum number of retries.
    pub max_retries: u32,
    /// Initial backoff duration.
    pub initial_backoff: Duration,
    /// Maximum backoff duration.
    pub max_backoff: Duration,
    /// Backoff multiplier.
    pub multiplier: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(10),
            multiplier: 2.0,
        }
    }
}

impl RetryConfig {
    /// Create a new retry config with no retries.
    pub fn no_retry() -> Self {
        Self {
            max_retries: 0,
            ..Default::default()
        }
    }

    /// Create a retry config for idempotent operations.
    pub fn idempotent() -> Self {
        Self {
            max_retries: 5,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(30),
            multiplier: 2.0,
        }
    }
}

/// Retry a fallible async operation.
pub async fn retry<F, T, E, Fut>(config: &RetryConfig, mut operation: F) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, E>>,
    E: std::fmt::Display,
{
    let mut attempt = 0;
    let mut backoff = config.initial_backoff;

    loop {
        match operation().await {
            Ok(result) => return Ok(result),
            Err(e) => {
                attempt += 1;
                if attempt > config.max_retries {
                    return Err(e);
                }

                crate::diagnostics::log_warn(format!(
                    "retry {}/{} after error: {}",
                    attempt, config.max_retries, e
                ));

                // Wait before retrying
                sleep(backoff).await;

                // Calculate next backoff
                backoff = Duration::from_secs_f64(
                    (backoff.as_secs_f64() * config.multiplier)
                        .min(config.max_backoff.as_secs_f64()),
                );
            }
        }
    }
}

/// Check if an error is retryable.
pub fn is_retryable_error(status: reqwest::StatusCode) -> bool {
    matches!(
        status,
        reqwest::StatusCode::REQUEST_TIMEOUT
            | reqwest::StatusCode::TOO_MANY_REQUESTS
            | reqwest::StatusCode::INTERNAL_SERVER_ERROR
            | reqwest::StatusCode::BAD_GATEWAY
            | reqwest::StatusCode::SERVICE_UNAVAILABLE
            | reqwest::StatusCode::GATEWAY_TIMEOUT
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn retry_succeeds_on_first_try() {
        let config = RetryConfig::default();
        let mut attempts = 0;

        let result: Result<i32, &str> = retry(&config, || {
            attempts += 1;
            async { Ok(42) }
        })
        .await;

        assert_eq!(result, Ok(42));
        assert_eq!(attempts, 1);
    }

    #[tokio::test]
    async fn retry_succeeds_after_failures() {
        let config = RetryConfig {
            max_retries: 3,
            initial_backoff: Duration::from_millis(1),
            ..Default::default()
        };
        let mut attempts = 0;

        let result: Result<i32, &str> = retry(&config, || {
            attempts += 1;
            async move {
                if attempts < 3 {
                    Err("temporary failure")
                } else {
                    Ok(42)
                }
            }
        })
        .await;

        assert_eq!(result, Ok(42));
        assert_eq!(attempts, 3);
    }

    #[tokio::test]
    async fn retry_gives_up_after_max_retries() {
        let config = RetryConfig {
            max_retries: 2,
            initial_backoff: Duration::from_millis(1),
            ..Default::default()
        };
        let mut attempts = 0;

        let result: Result<i32, &str> = retry(&config, || {
            attempts += 1;
            async { Err("permanent failure") }
        })
        .await;

        assert!(result.is_err());
        assert_eq!(attempts, 3); // 1 initial + 2 retries
    }
}
