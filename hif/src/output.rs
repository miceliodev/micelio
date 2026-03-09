//! Output helpers for human and machine-readable CLI responses.

use crate::error::{MicError, Result};
use serde::Serialize;
use serde_json::Value;

/// Whether JSON output mode is enabled for this process.
pub fn use_json() -> bool {
    crate::cli::should_use_json()
}

/// Print a serializable value as pretty JSON.
pub fn print_json<T: Serialize>(value: &T) -> Result<()> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|e| MicError::Other(format!("Failed to serialize JSON output: {}", e)))?;
    println!("{}", json);
    Ok(())
}

/// Print a standard success envelope for machine-readable output.
pub fn print_ok(action: &str, data: Value) -> Result<()> {
    print_json(&serde_json::json!({
        "status": "ok",
        "action": action,
        "data": data
    }))
}
