//! Output helpers for human and machine-readable CLI responses.

use crate::error::{MicError, Result};
use colored::Colorize;
use serde::Serialize;
use std::sync::{Mutex, OnceLock};
use toon_format::encode_default;

/// Convert command/domain values into explicit CLI JSON models.
pub(crate) trait CliOutput {
    type Model: Serialize;

    fn into_cli_output(self) -> Self::Model;
}

impl<T> CliOutput for Vec<T>
where
    T: CliOutput,
{
    type Model = Vec<T::Model>;

    fn into_cli_output(self) -> Self::Model {
        self.into_iter().map(T::into_cli_output).collect()
    }
}

#[derive(Default)]
struct LifecycleState {
    warnings: Vec<String>,
    success_message: Option<String>,
    next_steps: Vec<String>,
}

#[derive(Serialize)]
struct SuccessEnvelope<'a, T: Serialize> {
    status: &'static str,
    action: &'a str,
    data: T,
    #[serde(skip_serializing_if = "Option::is_none")]
    warnings: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    next_steps: Option<Vec<String>>,
}

fn lifecycle_state() -> &'static Mutex<LifecycleState> {
    static STATE: OnceLock<Mutex<LifecycleState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(LifecycleState::default()))
}

/// Reset lifecycle output state for a command invocation.
pub fn reset_lifecycle() {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    state.warnings.clear();
    state.success_message = None;
    state.next_steps.clear();
}

/// Record a warning to be emitted at command exit.
pub fn warn(message: impl Into<String>) {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    state.warnings.push(message.into());
}

/// Take and clear any collected warnings.
pub fn take_warnings() -> Vec<String> {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    std::mem::take(&mut state.warnings)
}

/// Set a standardized success message to print at command exit (human mode).
pub fn set_success_message(message: impl Into<String>) {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    state.success_message = Some(message.into());
}

/// Add a next step to print at command exit (human mode) and include in structured output.
pub fn add_next_step(step: impl Into<String>) {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    state.next_steps.push(step.into());
}

/// Take and clear the success message.
pub fn take_success_message() -> Option<String> {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    state.success_message.take()
}

/// Take and clear any collected next steps.
pub fn take_next_steps() -> Vec<String> {
    let mut state = lifecycle_state()
        .lock()
        .expect("output lifecycle state mutex poisoned");
    std::mem::take(&mut state.next_steps)
}

/// Print warnings in a standardized human-readable format.
pub fn print_human_warnings(warnings: &[String], to_stderr: bool) {
    for warning in warnings {
        if to_stderr {
            eprintln!("{} {}", "warning:".yellow().bold(), warning);
        } else {
            println!("{} {}", "warning:".yellow().bold(), warning);
        }
    }
}

/// Print a standardized human success line.
pub fn print_human_success(message: &str) {
    println!("{}", message);
}

/// Print next steps in a standardized human-readable format.
pub fn print_human_next_steps(next_steps: &[String]) {
    if next_steps.is_empty() {
        return;
    }

    println!("{}", "Next steps:".bold());
    for step in next_steps {
        println!("  {}", step);
    }
}

/// Whether JSON output mode is enabled for this process.
pub fn use_json() -> bool {
    crate::cli::should_use_json() || crate::cli::should_use_toon()
}

/// Whether TOON output mode is enabled for this process.
pub fn use_toon() -> bool {
    crate::cli::should_use_toon()
}

/// Print a serializable value as pretty JSON.
pub fn print_json<T: Serialize>(value: &T) -> Result<()> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|e| MicError::Other(format!("Failed to serialize JSON output: {}", e)))?;
    println!("{}", json);
    Ok(())
}

/// Print a serializable value as TOON.
pub fn print_toon<T: Serialize>(value: &T) -> Result<()> {
    let toon = encode_default(value)
        .map_err(|e| MicError::Other(format!("Failed to serialize TOON output: {}", e)))?;
    println!("{}", toon);
    Ok(())
}

/// Print a serializable value in the selected structured format (JSON or TOON).
pub fn print_structured<T: Serialize>(value: &T) -> Result<()> {
    if use_toon() {
        print_toon(value)
    } else {
        print_json(value)
    }
}

/// Print a standard success envelope for machine-readable output.
pub fn print_ok<T: Serialize>(action: &str, data: T) -> Result<()> {
    let warnings = take_warnings();
    let next_steps = take_next_steps();
    let envelope = SuccessEnvelope {
        status: "ok",
        action,
        data,
        warnings: (!warnings.is_empty()).then_some(warnings),
        next_steps: (!next_steps.is_empty()).then_some(next_steps),
    };
    print_structured(&envelope)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lifecycle_warnings_round_trip() {
        reset_lifecycle();
        warn("first warning");
        warn("second warning");

        let warnings = take_warnings();
        assert_eq!(warnings, vec!["first warning", "second warning"]);
        assert!(take_warnings().is_empty());
    }

    #[test]
    fn lifecycle_success_message_round_trip() {
        reset_lifecycle();
        set_success_message("done");

        assert_eq!(take_success_message().as_deref(), Some("done"));
        assert!(take_success_message().is_none());
    }

    #[test]
    fn lifecycle_next_steps_round_trip() {
        reset_lifecycle();
        add_next_step("cd repo");
        add_next_step("hif session start \"goal\"");

        let next_steps = take_next_steps();
        assert_eq!(next_steps, vec!["cd repo", "hif session start \"goal\""]);
        assert!(take_next_steps().is_empty());
    }
}
