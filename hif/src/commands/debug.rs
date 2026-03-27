//! Diagnostics inspection commands.

use crate::cli::{DebugCommand, DebugSubcommand};
use crate::diagnostics::{self, GrpcDebugEntry, RequestSummary, StoredSession};
use crate::error::Result;
use crate::output;
use serde::Serialize;

#[derive(Serialize)]
struct DebugSessionOutput {
    id: String,
    started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    ended_at: Option<String>,
    pid: u32,
    argv: Vec<String>,
    cwd: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    requested_cwd: Option<String>,
    verbose: bool,
    output_mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    exit_code: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    previous_session_id: Option<String>,
    dir: String,
    session_file: String,
    verbose_log_file: String,
    network_har_file: String,
    grpc_messages_file: String,
    request_count: usize,
    grpc_exchange_count: usize,
}

#[derive(Serialize)]
struct DebugLogsOutput {
    session_id: String,
    path: String,
    content: String,
}

#[derive(Serialize)]
struct DebugPathOutput {
    session_id: String,
    path: String,
}

#[derive(Serialize)]
struct DebugRequestsOutput {
    session_id: String,
    requests: Vec<RequestSummary>,
}

#[derive(Serialize)]
struct DebugGrpcOutput {
    session_id: String,
    exchanges: Vec<GrpcDebugEntry>,
}

pub async fn run(cmd: DebugCommand) -> Result<()> {
    match cmd.command {
        DebugSubcommand::Latest => show(None, "debug.latest"),
        DebugSubcommand::Show { session } => show(session.as_deref(), "debug.show"),
        DebugSubcommand::Logs { session } => logs(session.as_deref()),
        DebugSubcommand::Requests { session } => requests(session.as_deref()),
        DebugSubcommand::Grpc { session } => grpc(session.as_deref()),
        DebugSubcommand::Path { session } => path(session.as_deref()),
    }
}

fn show(reference: Option<&str>, action: &str) -> Result<()> {
    let session = diagnostics::resolve_debug_session(reference)?;
    let request_count = diagnostics::read_request_summaries(&session)?.len();
    let grpc_exchange_count = diagnostics::read_grpc_entries(&session)?.len();
    let output = DebugSessionOutput {
        id: session.id.clone(),
        started_at: session.started_at.clone(),
        ended_at: session.ended_at.clone(),
        pid: session.pid,
        argv: session.argv.clone(),
        cwd: session.cwd.clone(),
        requested_cwd: session.requested_cwd.clone(),
        verbose: session.verbose,
        output_mode: session.output_mode.clone(),
        exit_code: session.exit_code,
        previous_session_id: session.previous_session_id.clone(),
        dir: session.dir.display().to_string(),
        session_file: session.session_file.display().to_string(),
        verbose_log_file: session.verbose_log_file.display().to_string(),
        network_har_file: session.network_har_file.display().to_string(),
        grpc_messages_file: session.grpc_messages_file.display().to_string(),
        request_count,
        grpc_exchange_count,
    };

    if output::use_json() {
        output::print_ok(action, output)?;
    } else {
        print_session_summary(&output, &session);
    }

    Ok(())
}

fn logs(reference: Option<&str>) -> Result<()> {
    let session = diagnostics::resolve_debug_session(reference)?;
    let content = diagnostics::read_verbose_log(&session)?;
    if output::use_json() {
        output::print_ok(
            "debug.logs",
            DebugLogsOutput {
                session_id: session.id,
                path: session.verbose_log_file.display().to_string(),
                content,
            },
        )?;
    } else {
        output::ui_text(&content);
        if !content.is_empty() && !content.ends_with('\n') {
            output::ui_blank_line();
        }
    }
    Ok(())
}

fn requests(reference: Option<&str>) -> Result<()> {
    let session = diagnostics::resolve_debug_session(reference)?;
    let requests = diagnostics::read_request_summaries(&session)?;
    if output::use_json() {
        output::print_ok(
            "debug.requests",
            DebugRequestsOutput {
                session_id: session.id,
                requests,
            },
        )?;
    } else {
        print_request_summaries(&session, &requests);
    }
    Ok(())
}

fn grpc(reference: Option<&str>) -> Result<()> {
    let session = diagnostics::resolve_debug_session(reference)?;
    let exchanges = diagnostics::read_grpc_entries(&session)?;
    if output::use_json() {
        output::print_ok(
            "debug.grpc",
            DebugGrpcOutput {
                session_id: session.id,
                exchanges,
            },
        )?;
    } else {
        print_grpc_exchanges(&session, &exchanges);
    }
    Ok(())
}

fn path(reference: Option<&str>) -> Result<()> {
    let session = diagnostics::resolve_debug_session(reference)?;
    if output::use_json() {
        output::print_ok(
            "debug.path",
            DebugPathOutput {
                session_id: session.id,
                path: session.dir.display().to_string(),
            },
        )?;
    } else {
        output::ui_line(session.dir.display());
    }
    Ok(())
}

fn print_session_summary(output: &DebugSessionOutput, session: &StoredSession) {
    output::ui_kv("Diagnostics session", &output.id);
    output::ui_kv("Command", session.argv.join(" "));
    output::ui_kv("Started", &output.started_at);
    if let Some(ended_at) = &output.ended_at {
        output::ui_kv("Ended", ended_at);
    }
    if let Some(exit_code) = output.exit_code {
        output::ui_kv("Exit code", exit_code);
    }
    output::ui_kv("Output", &output.output_mode);
    output::ui_kv("Verbose", output.verbose);
    output::ui_kv("CWD", &output.cwd);
    if let Some(requested_cwd) = &output.requested_cwd {
        output::ui_kv("Requested cwd", requested_cwd);
    }
    output::ui_kv("Directory", &output.dir);
    output::ui_kv("session.json", &output.session_file);
    output::ui_kv("verbose.log", &output.verbose_log_file);
    output::ui_kv("network.har", format!("{} entries", output.request_count));
    output::ui_kv(
        "grpc.jsonl",
        format!("{} exchanges", output.grpc_exchange_count),
    );
}

fn print_request_summaries(session: &StoredSession, requests: &[RequestSummary]) {
    output::ui_kv("Persisted requests for", &session.id);
    if requests.is_empty() {
        output::ui_line("No persisted requests.");
        return;
    }

    for request in requests {
        output::ui_line(format!(
            "{} {} {} -> {} ({:.1} ms)",
            request.transport, request.method, request.url, request.status, request.duration_ms
        ));
    }
}

fn print_grpc_exchanges(session: &StoredSession, exchanges: &[GrpcDebugEntry]) {
    output::ui_kv("Persisted gRPC exchanges for", &session.id);
    if exchanges.is_empty() {
        output::ui_line("No persisted gRPC exchanges.");
        return;
    }

    for exchange in exchanges {
        output::ui_line(format!(
            "{} -> http {} grpc-status {} ({:.1} ms)",
            exchange.method,
            exchange.http_status,
            exchange.grpc_status.as_deref().unwrap_or("<none>"),
            exchange.duration_ms
        ));
        for message in &exchange.request_messages {
            output::ui_line(format!("request[{}] {} bytes", message.index, message.size));
        }
        for message in &exchange.response_messages {
            output::ui_line(format!(
                "response[{}] {} bytes",
                message.index, message.size
            ));
        }
        if let Some(error) = &exchange.error {
            output::ui_kv("error", error);
        }
        if let Some(parse_error) = &exchange.request_parse_error {
            output::ui_kv("request parse error", parse_error);
        }
        if let Some(parse_error) = &exchange.response_parse_error {
            output::ui_kv("response parse error", parse_error);
        }
    }
}
