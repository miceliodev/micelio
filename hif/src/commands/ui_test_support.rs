use std::path::Path;
use std::process::Output;

#[allow(deprecated)]
fn run_hif_snapshot(home: &Path, cwd: &Path, args: &[&str]) -> Output {
    let binary = assert_cmd::cargo::cargo_bin("hif");

    std::process::Command::new(binary)
        .arg("--no-color")
        .args(args)
        .current_dir(cwd)
        .env("HIF_HOME", home)
        .env("NO_COLOR", "1")
        .output()
        .expect("failed to run hif")
}

fn normalize(text: &[u8]) -> String {
    String::from_utf8_lossy(text).replace("\r\n", "\n")
}

pub(crate) fn assert_output_snapshot_with_setup<F>(
    args: &[&str],
    expected_code: i32,
    expected_stdout: &str,
    expected_stderr: &str,
    setup: F,
) where
    F: FnOnce(&Path, &Path),
{
    let home = tempfile::tempdir().expect("create HIF_HOME tempdir");
    let cwd = tempfile::tempdir().expect("create cwd tempdir");
    setup(home.path(), cwd.path());

    let output = run_hif_snapshot(home.path(), cwd.path(), args);

    assert_eq!(
        output.status.code(),
        Some(expected_code),
        "unexpected exit code for args {:?}",
        args
    );

    let stdout = normalize(&output.stdout);
    let stderr = normalize(&output.stderr);

    assert_eq!(
        stdout, expected_stdout,
        "stdout snapshot mismatch for args {:?}",
        args
    );
    assert_eq!(
        stderr, expected_stderr,
        "stderr snapshot mismatch for args {:?}",
        args
    );
}

pub(crate) fn assert_output_snapshot(
    args: &[&str],
    expected_code: i32,
    expected_stdout: &str,
    expected_stderr: &str,
) {
    assert_output_snapshot_with_setup(
        args,
        expected_code,
        expected_stdout,
        expected_stderr,
        |_home, _cwd| {},
    );
}
