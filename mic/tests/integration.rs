//! Integration tests for the mic CLI.
//!
//! These tests verify the CLI works correctly from an end-user perspective.

use assert_cmd::Command;
use predicates::prelude::*;

/// Get a command for the mic binary.
fn mic() -> Command {
    Command::cargo_bin("mic").unwrap()
}

// =============================================================================
// Help and Version Tests
// =============================================================================

#[test]
fn cli_shows_help() {
    mic()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("Micelio CLI"))
        .stdout(predicate::str::contains("Usage:"))
        .stdout(predicate::str::contains("auth"))
        .stdout(predicate::str::contains("project"))
        .stdout(predicate::str::contains("session"));
}

#[test]
fn cli_shows_version() {
    mic()
        .arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("mic"));
}

#[test]
fn subcommand_help_works() {
    mic()
        .args(["auth", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("login"))
        .stdout(predicate::str::contains("status"))
        .stdout(predicate::str::contains("logout"));
}

// =============================================================================
// Auth Status Tests
// =============================================================================

#[test]
fn auth_status_when_not_logged_in() {
    // Use a temp directory for config to avoid affecting real config
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .args(["auth", "status"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Not logged in"));
}

#[test]
fn auth_logout_when_not_logged_in() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .args(["auth", "logout"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Logged out"));
}

// =============================================================================
// Workspace Tests
// =============================================================================

#[test]
fn status_outside_workspace() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .current_dir(temp_dir.path())
        .arg("status")
        .assert()
        .failure()
        .stderr(predicate::str::contains("No workspace"));
}

#[test]
fn status_with_cwd_flag() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .args(["-C", temp_dir.path().to_str().unwrap(), "status"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("No workspace"));
}

// =============================================================================
// Session Tests
// =============================================================================

#[test]
fn session_status_without_workspace() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    // Session status outside a workspace shows "No active session" message
    mic()
        .env("MIC_HOME", temp_dir.path())
        .current_dir(temp_dir.path())
        .args(["session", "status"])
        .assert()
        .success()
        .stdout(predicate::str::contains("No active session"));
}

#[test]
fn session_land_without_session() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .current_dir(temp_dir.path())
        .args(["session", "land"])
        .assert()
        .failure();
}

// =============================================================================
// Error Format Tests
// =============================================================================

#[test]
fn json_error_format() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .current_dir(temp_dir.path())
        .args(["--json", "status"])
        .assert()
        .failure()
        .stderr(predicate::str::contains(r#""status": "error""#))
        .stderr(predicate::str::contains(r#""code":"#));
}

// =============================================================================
// Help JSON Tests (for agents)
// =============================================================================

#[test]
fn help_json_is_valid_json() {
    let output = mic()
        .args(["--help", "--json"])
        .assert()
        .success();
    
    let stdout = String::from_utf8_lossy(&output.get_output().stdout);
    let parsed: serde_json::Value = serde_json::from_str(&stdout)
        .expect("--help --json should output valid JSON");
    
    // Verify key fields exist
    assert!(parsed.get("name").is_some());
    assert!(parsed.get("version").is_some());
    assert!(parsed.get("commands").is_some());
    assert!(parsed.get("workflow").is_some());
    assert!(parsed.get("concepts").is_some());
    assert!(parsed.get("error_codes").is_some());
}

#[test]
fn help_json_has_all_commands() {
    let output = mic()
        .args(["--help", "--json"])
        .assert()
        .success();
    
    let stdout = String::from_utf8_lossy(&output.get_output().stdout);
    let parsed: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    let commands = parsed.get("commands").unwrap().as_object().unwrap();
    
    // Verify key commands are documented
    assert!(commands.contains_key("auth"));
    assert!(commands.contains_key("checkout"));
    assert!(commands.contains_key("session"));
    assert!(commands.contains_key("status"));
    assert!(commands.contains_key("land"));
}

// =============================================================================
// Project Reference Parsing Tests
// =============================================================================

#[test]
fn invalid_project_ref_in_checkout() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    // Missing slash
    mic()
        .env("MIC_HOME", temp_dir.path())
        .current_dir(temp_dir.path())
        .args(["checkout", "invalid"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Invalid project"));
}

// =============================================================================
// Org Command Tests
// =============================================================================

#[test]
fn org_list_requires_auth() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .args(["org", "list"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Not authenticated"));
}

#[test]
fn project_list_requires_auth() {
    let temp_dir = tempfile::tempdir().unwrap();
    
    mic()
        .env("MIC_HOME", temp_dir.path())
        .args(["project", "list", "myorg"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("Not authenticated"));
}
