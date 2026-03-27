//! Persistent diagnostics for CLI invocations.

use crate::error::{MicError, Result};
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine;
use chrono::{SecondsFormat, Utc};
use reqwest::Version;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use url::Url;

const BODY_CAPTURE_LIMIT: usize = 64 * 1024;
const REDACTED: &str = "<redacted>";

#[derive(Clone, Debug)]
pub struct SessionInfo {
    pub id: String,
    pub dir: PathBuf,
    pub session_file: PathBuf,
    pub verbose_log_file: PathBuf,
    pub network_har_file: PathBuf,
    pub grpc_messages_file: PathBuf,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct SessionMetadata {
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
    #[serde(skip_serializing_if = "Option::is_none")]
    command_name: Option<String>,
}

struct DiagnosticsSession {
    info: SessionInfo,
    metadata: SessionMetadata,
    har: HarRoot,
}

#[derive(Default)]
struct DiagnosticsState {
    current: Option<DiagnosticsSession>,
}

#[derive(Clone)]
pub(crate) struct CapturedBody {
    mime_type: String,
    text: String,
    encoding: Option<&'static str>,
    size: usize,
    truncated: bool,
}

pub(crate) struct NetworkExchange {
    pub kind: &'static str,
    pub started_at: String,
    pub duration: Duration,
    pub method: String,
    pub url: String,
    pub http_version: Option<String>,
    pub request_headers: Vec<(String, String)>,
    pub request_body: Option<CapturedBody>,
    pub response_status: u16,
    pub response_status_text: String,
    pub response_headers: Vec<(String, String)>,
    pub response_body: Option<CapturedBody>,
    pub error: Option<String>,
}

pub(crate) struct GrpcExchange {
    pub started_at: String,
    pub duration: Duration,
    pub method: String,
    pub url: String,
    pub http_version: Option<String>,
    pub http_status: u16,
    pub request_headers: Vec<(String, String)>,
    pub response_headers: Vec<(String, String)>,
    pub grpc_status: Option<String>,
    pub grpc_message: Option<String>,
    pub request_body: Vec<u8>,
    pub response_body: Option<Vec<u8>>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct GrpcDebugEntry {
    pub started_at: String,
    pub duration_ms: f64,
    pub method: String,
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_version: Option<String>,
    pub http_status: u16,
    pub request_headers: Vec<(String, String)>,
    pub response_headers: Vec<(String, String)>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grpc_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grpc_message: Option<String>,
    pub request_messages: Vec<GrpcMessageFrame>,
    pub response_messages: Vec<GrpcMessageFrame>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_parse_error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_parse_error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct GrpcMessageFrame {
    pub index: usize,
    pub compressed: bool,
    pub size: usize,
    pub encoding: String,
    pub payload: String,
}

#[derive(Deserialize, Serialize)]
struct HarRoot {
    log: HarLog,
}

#[derive(Deserialize, Serialize)]
struct HarLog {
    version: String,
    creator: HarCreator,
    entries: Vec<HarEntry>,
}

#[derive(Deserialize, Serialize)]
struct HarCreator {
    name: String,
    version: String,
}

#[derive(Deserialize, Serialize)]
struct HarEntry {
    #[serde(rename = "startedDateTime")]
    started_date_time: String,
    time: f64,
    request: HarRequest,
    response: HarResponse,
    cache: HarCache,
    timings: HarTimings,
    #[serde(skip_serializing_if = "Option::is_none")]
    comment: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct HarRequest {
    method: String,
    url: String,
    #[serde(rename = "httpVersion")]
    http_version: String,
    headers: Vec<HarHeader>,
    #[serde(rename = "queryString")]
    query_string: Vec<HarQueryParam>,
    cookies: Vec<HarCookie>,
    #[serde(rename = "headersSize")]
    headers_size: i64,
    #[serde(rename = "bodySize")]
    body_size: i64,
    #[serde(skip_serializing_if = "Option::is_none", rename = "postData")]
    post_data: Option<HarPostData>,
}

#[derive(Deserialize, Serialize)]
struct HarResponse {
    status: u16,
    #[serde(rename = "statusText")]
    status_text: String,
    #[serde(rename = "httpVersion")]
    http_version: String,
    headers: Vec<HarHeader>,
    cookies: Vec<HarCookie>,
    content: HarContent,
    #[serde(rename = "redirectURL")]
    redirect_url: String,
    #[serde(rename = "headersSize")]
    headers_size: i64,
    #[serde(rename = "bodySize")]
    body_size: i64,
}

#[derive(Deserialize, Serialize)]
struct HarHeader {
    name: String,
    value: String,
}

#[derive(Deserialize, Serialize)]
struct HarQueryParam {
    name: String,
    value: String,
}

#[derive(Deserialize, Serialize)]
struct HarCookie {}

#[derive(Deserialize, Serialize)]
struct HarPostData {
    #[serde(rename = "mimeType")]
    mime_type: String,
    text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    encoding: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    comment: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct HarContent {
    size: i64,
    #[serde(rename = "mimeType")]
    mime_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    encoding: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    comment: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct HarCache {}

#[derive(Deserialize, Serialize)]
struct HarTimings {
    send: f64,
    wait: f64,
    receive: f64,
}

#[derive(Clone, Debug, Serialize)]
pub struct StoredSession {
    pub id: String,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub pid: u32,
    pub argv: Vec<String>,
    pub cwd: String,
    pub requested_cwd: Option<String>,
    pub verbose: bool,
    pub output_mode: String,
    pub exit_code: Option<i32>,
    pub previous_session_id: Option<String>,
    pub command_name: Option<String>,
    pub dir: PathBuf,
    pub session_file: PathBuf,
    pub verbose_log_file: PathBuf,
    pub network_har_file: PathBuf,
    pub grpc_messages_file: PathBuf,
}

#[derive(Clone, Debug, Serialize)]
pub struct RequestSummary {
    pub started_at: String,
    pub method: String,
    pub url: String,
    pub status: u16,
    pub duration_ms: f64,
    pub transport: String,
    pub comment: Option<String>,
}

impl Default for HarRoot {
    fn default() -> Self {
        Self {
            log: HarLog {
                version: "1.2".to_string(),
                creator: HarCreator {
                    name: "hif".to_string(),
                    version: env!("CARGO_PKG_VERSION").to_string(),
                },
                entries: Vec::new(),
            },
        }
    }
}

fn diagnostics_state() -> &'static Mutex<DiagnosticsState> {
    static STATE: OnceLock<Mutex<DiagnosticsState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(DiagnosticsState::default()))
}

pub fn init(
    args: &[String],
    cwd: &Path,
    requested_cwd: Option<&Path>,
    verbose: bool,
    output_mode: &str,
    command_name: Option<&str>,
) -> Result<SessionInfo> {
    let state_root = crate::config::ensure_state_dir()?;
    let session = create_session(
        &state_root,
        args,
        cwd,
        requested_cwd,
        verbose,
        output_mode,
        command_name,
    )?;
    session.append_event(
        "INFO",
        &format!(
            "diagnostics session started id={} output_mode={} verbose={}",
            session.info.id, output_mode, verbose
        ),
    )?;

    let info = session.info.clone();
    let mut state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    state.current = Some(session);
    Ok(info)
}

pub fn finish(exit_code: i32) {
    let mut state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    if let Some(mut session) = state.current.take() {
        let _ = session.finish(exit_code);
    }
}

pub fn current_session_id() -> Option<String> {
    let state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    state
        .current
        .as_ref()
        .map(|session| session.info.id.clone())
}

pub fn previous_session_id() -> Option<String> {
    let state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    state
        .current
        .as_ref()
        .and_then(|session| session.metadata.previous_session_id.clone())
}

pub fn log_info(message: impl AsRef<str>) {
    log_event("INFO", message.as_ref(), false);
}

pub fn log_warn(message: impl AsRef<str>) {
    log_event("WARN", message.as_ref(), false);
}

pub fn log_error(message: impl AsRef<str>) {
    log_event("ERROR", message.as_ref(), false);
}

pub fn log_debug(message: impl AsRef<str>) {
    log_event("DEBUG", message.as_ref(), true);
}

pub(crate) fn record_network_exchange(exchange: NetworkExchange) {
    let mut state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    if let Some(session) = state.current.as_mut() {
        let _ = session.append_network_exchange(exchange);
    }
}

pub(crate) fn record_grpc_exchange(exchange: GrpcExchange) {
    let mut state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    if let Some(session) = state.current.as_mut() {
        let _ = session.append_grpc_exchange(exchange);
    }
}

pub(crate) fn timestamp_now() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}

pub(crate) fn http_version_label(version: Version) -> String {
    match version {
        Version::HTTP_09 => "HTTP/0.9".to_string(),
        Version::HTTP_10 => "HTTP/1.0".to_string(),
        Version::HTTP_11 => "HTTP/1.1".to_string(),
        Version::HTTP_2 => "HTTP/2".to_string(),
        Version::HTTP_3 => "HTTP/3".to_string(),
        _ => "HTTP".to_string(),
    }
}

pub(crate) fn header_pairs(headers: &reqwest::header::HeaderMap) -> Vec<(String, String)> {
    headers
        .iter()
        .map(|(name, value)| {
            (
                name.as_str().to_string(),
                sanitize_header_value(name.as_str(), value.to_str().unwrap_or("<binary>")),
            )
        })
        .collect()
}

pub(crate) fn capture_json_body(text: &str) -> CapturedBody {
    capture_text_body_with_kind(text, "application/json", BodyKind::Json)
}

pub(crate) fn capture_form_body(text: &str) -> CapturedBody {
    capture_text_body_with_kind(text, "application/x-www-form-urlencoded", BodyKind::Form)
}

pub(crate) fn capture_text_body(text: &str, mime_type: &str) -> CapturedBody {
    let normalized = mime_type.to_ascii_lowercase();
    if normalized.contains("application/json") || normalized.contains("+json") {
        capture_text_body_with_kind(text, mime_type, BodyKind::Json)
    } else if normalized.contains("application/x-www-form-urlencoded") {
        capture_text_body_with_kind(text, mime_type, BodyKind::Form)
    } else {
        capture_text_body_with_kind(text, mime_type, BodyKind::Plain)
    }
}

pub(crate) fn capture_binary_body(bytes: &[u8], mime_type: &str) -> CapturedBody {
    let truncated = bytes.len() > BODY_CAPTURE_LIMIT;
    let slice = if truncated {
        &bytes[..BODY_CAPTURE_LIMIT]
    } else {
        bytes
    };

    CapturedBody {
        mime_type: mime_type.to_string(),
        text: BASE64_STANDARD.encode(slice),
        encoding: Some("base64"),
        size: bytes.len(),
        truncated,
    }
}

fn log_event(level: &str, message: &str, debug_only: bool) {
    let mut state = diagnostics_state()
        .lock()
        .expect("diagnostics state mutex poisoned");
    if let Some(session) = state.current.as_mut() {
        if debug_only && !session.metadata.verbose {
            return;
        }
        let _ = session.append_event(level, message);
    }
}

fn create_session(
    state_root: &Path,
    args: &[String],
    cwd: &Path,
    requested_cwd: Option<&Path>,
    verbose: bool,
    output_mode: &str,
    command_name: Option<&str>,
) -> Result<DiagnosticsSession> {
    let started_at = timestamp_now();
    let id = uuid::Uuid::now_v7().to_string();
    let sessions_dir = state_root.join("sessions");
    fs::create_dir_all(&sessions_dir)?;
    let previous_session_id = read_latest_session_id_from(state_root)?;

    let dir = sessions_dir.join(&id);
    fs::create_dir_all(&dir)?;

    let info = SessionInfo {
        id: id.clone(),
        session_file: dir.join("session.json"),
        verbose_log_file: dir.join("verbose.log"),
        network_har_file: dir.join("network.har"),
        grpc_messages_file: dir.join("grpc.jsonl"),
        dir: dir.clone(),
    };

    let metadata = SessionMetadata {
        id: id.clone(),
        started_at,
        ended_at: None,
        pid: std::process::id(),
        argv: args.to_vec(),
        cwd: cwd.display().to_string(),
        requested_cwd: requested_cwd.map(|path| path.display().to_string()),
        verbose,
        output_mode: output_mode.to_string(),
        exit_code: None,
        previous_session_id,
        command_name: command_name.map(str::to_string),
    };

    let session = DiagnosticsSession {
        info,
        metadata,
        har: HarRoot::default(),
    };

    write_json_atomic(&session.info.session_file, &session.metadata)?;
    write_json_atomic(&session.info.network_har_file, &session.har)?;
    fs::write(&session.info.grpc_messages_file, b"")?;
    fs::write(
        state_root.join("latest-session"),
        format!("{}\n{}\n", id, dir.display()),
    )?;

    Ok(session)
}

impl DiagnosticsSession {
    fn finish(&mut self, exit_code: i32) -> Result<()> {
        self.metadata.ended_at = Some(timestamp_now());
        self.metadata.exit_code = Some(exit_code);
        self.append_event("INFO", &format!("command finished exit_code={}", exit_code))?;
        write_json_atomic(&self.info.session_file, &self.metadata)
    }

    fn append_event(&self, level: &str, message: &str) -> Result<()> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.info.verbose_log_file)?;
        writeln!(file, "{} {:<5} {}", timestamp_now(), level, message)?;
        Ok(())
    }

    fn append_network_exchange(&mut self, exchange: NetworkExchange) -> Result<()> {
        let request_url = exchange.url.clone();
        let request_method = exchange.method.clone();
        let request_version = exchange
            .http_version
            .clone()
            .unwrap_or_else(|| "HTTP".to_string());
        let comment = match exchange.error {
            Some(error) => format!("transport={} error={}", exchange.kind, error),
            None => format!("transport={}", exchange.kind),
        };

        let entry = HarEntry {
            started_date_time: exchange.started_at,
            time: exchange.duration.as_secs_f64() * 1000.0,
            request: HarRequest {
                method: request_method.clone(),
                url: redact_url(&request_url),
                http_version: request_version.clone(),
                headers: exchange
                    .request_headers
                    .into_iter()
                    .map(|(name, value)| HarHeader { name, value })
                    .collect(),
                query_string: query_params(&request_url),
                cookies: Vec::new(),
                headers_size: -1,
                body_size: exchange
                    .request_body
                    .as_ref()
                    .map(|body| body.size as i64)
                    .unwrap_or(0),
                post_data: exchange.request_body.as_ref().map(har_post_data),
            },
            response: HarResponse {
                status: exchange.response_status,
                status_text: exchange.response_status_text,
                http_version: request_version,
                headers: exchange
                    .response_headers
                    .into_iter()
                    .map(|(name, value)| HarHeader { name, value })
                    .collect(),
                cookies: Vec::new(),
                content: har_content(exchange.response_body.as_ref()),
                redirect_url: String::new(),
                headers_size: -1,
                body_size: exchange
                    .response_body
                    .as_ref()
                    .map(|body| body.size as i64)
                    .unwrap_or(0),
            },
            cache: HarCache {},
            timings: HarTimings {
                send: 0.0,
                wait: exchange.duration.as_secs_f64() * 1000.0,
                receive: 0.0,
            },
            comment: Some(comment),
        };

        self.har.log.entries.push(entry);
        self.append_event(
            "INFO",
            &format!(
                "{} request {} {} -> {}",
                exchange.kind, request_method, request_url, exchange.response_status
            ),
        )?;
        write_json_atomic(&self.info.network_har_file, &self.har)
    }

    fn append_grpc_exchange(&mut self, exchange: GrpcExchange) -> Result<()> {
        let (request_messages, request_parse_error) = parse_grpc_messages(&exchange.request_body);
        let (response_messages, response_parse_error) = exchange
            .response_body
            .as_deref()
            .map(parse_grpc_messages)
            .unwrap_or_else(|| (Vec::new(), None));

        let entry = GrpcDebugEntry {
            started_at: exchange.started_at.clone(),
            duration_ms: exchange.duration.as_secs_f64() * 1000.0,
            method: exchange.method.clone(),
            url: redact_url(&exchange.url),
            http_version: exchange.http_version,
            http_status: exchange.http_status,
            request_headers: exchange.request_headers,
            response_headers: exchange.response_headers,
            grpc_status: exchange.grpc_status,
            grpc_message: exchange.grpc_message,
            request_messages,
            response_messages,
            request_parse_error,
            response_parse_error,
            error: exchange.error,
        };

        append_json_line(&self.info.grpc_messages_file, &entry)?;
        self.append_event(
            "INFO",
            &format!(
                "grpc messages {} -> status={} grpc-status={}",
                entry.method,
                entry.http_status,
                entry.grpc_status.as_deref().unwrap_or("<none>")
            ),
        )
    }
}

fn har_post_data(body: &CapturedBody) -> HarPostData {
    HarPostData {
        mime_type: body.mime_type.clone(),
        text: body.text.clone(),
        encoding: body.encoding.map(str::to_string),
        comment: body
            .truncated
            .then_some(format!("truncated to {} bytes", BODY_CAPTURE_LIMIT)),
    }
}

fn har_content(body: Option<&CapturedBody>) -> HarContent {
    match body {
        Some(body) => HarContent {
            size: body.size as i64,
            mime_type: body.mime_type.clone(),
            text: Some(body.text.clone()),
            encoding: body.encoding.map(str::to_string),
            comment: body
                .truncated
                .then_some(format!("truncated to {} bytes", BODY_CAPTURE_LIMIT)),
        },
        None => HarContent {
            size: 0,
            mime_type: "application/octet-stream".to_string(),
            text: None,
            encoding: None,
            comment: None,
        },
    }
}

fn query_params(url: &str) -> Vec<HarQueryParam> {
    let Ok(parsed) = Url::parse(url) else {
        return Vec::new();
    };

    parsed
        .query_pairs()
        .map(|(name, value)| HarQueryParam {
            name: name.to_string(),
            value: redact_if_sensitive(&name, &value),
        })
        .collect()
}

fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let data = serde_json::to_vec_pretty(value).map_err(|error| {
        MicError::Other(format!("Failed to serialize diagnostics JSON: {}", error))
    })?;

    let file_name = path
        .file_name()
        .ok_or_else(|| MicError::Other("Invalid diagnostics file path".to_string()))?
        .to_string_lossy();
    let tmp_path = path.with_file_name(format!(
        "{}.tmp.{}.{}",
        file_name,
        std::process::id(),
        uuid::Uuid::now_v7()
    ));

    let write_result = (|| -> Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp_path)?;
        file.write_all(&data)?;
        file.sync_all()?;
        fs::rename(&tmp_path, path)?;
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }

    write_result
}

fn append_json_line<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    serde_json::to_writer(&mut file, value).map_err(|error| {
        MicError::Other(format!(
            "Failed to serialize diagnostics JSON line: {}",
            error
        ))
    })?;
    file.write_all(b"\n")?;
    file.flush()?;
    Ok(())
}

fn parse_grpc_messages(body: &[u8]) -> (Vec<GrpcMessageFrame>, Option<String>) {
    let mut messages = Vec::new();
    let mut pos = 0usize;

    while pos < body.len() {
        if body.len() - pos < 5 {
            return (
                messages,
                Some(format!(
                    "Malformed gRPC frame stream: expected 5-byte header, found {} byte(s)",
                    body.len() - pos
                )),
            );
        }

        let compressed = body[pos] != 0;
        let size = u32::from_be_bytes([body[pos + 1], body[pos + 2], body[pos + 3], body[pos + 4]])
            as usize;
        pos += 5;

        if body.len() - pos < size {
            return (
                messages,
                Some(format!(
                    "Malformed gRPC frame stream: declared {} byte(s), found {} byte(s)",
                    size,
                    body.len() - pos
                )),
            );
        }

        let payload = &body[pos..pos + size];
        messages.push(GrpcMessageFrame {
            index: messages.len(),
            compressed,
            size,
            encoding: "base64".to_string(),
            payload: BASE64_STANDARD.encode(payload),
        });
        pos += size;
    }

    (messages, None)
}

fn read_latest_session_id_from(state_root: &Path) -> Result<Option<String>> {
    let path = state_root.join("latest-session");
    match fs::read_to_string(path) {
        Ok(contents) => Ok(contents
            .lines()
            .next()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

pub fn latest_session_id() -> Result<Option<String>> {
    let state_root = crate::config::state_dir()?;
    read_latest_session_id_from(&state_root)
}

pub fn load_session(id: &str) -> Result<StoredSession> {
    let state_root = crate::config::state_dir()?;
    let dir = state_root.join("sessions").join(id);
    let session_file = dir.join("session.json");
    let verbose_log_file = dir.join("verbose.log");
    let network_har_file = dir.join("network.har");
    let grpc_messages_file = dir.join("grpc.jsonl");

    if !session_file.exists() {
        return Err(MicError::DiagnosticsSessionNotFound(id.to_string()));
    }

    let metadata: SessionMetadata = serde_json::from_str(&fs::read_to_string(&session_file)?)?;
    Ok(StoredSession {
        id: metadata.id,
        started_at: metadata.started_at,
        ended_at: metadata.ended_at,
        pid: metadata.pid,
        argv: metadata.argv,
        cwd: metadata.cwd,
        requested_cwd: metadata.requested_cwd,
        verbose: metadata.verbose,
        output_mode: metadata.output_mode,
        exit_code: metadata.exit_code,
        previous_session_id: metadata.previous_session_id,
        command_name: metadata.command_name,
        dir,
        session_file,
        verbose_log_file,
        network_har_file,
        grpc_messages_file,
    })
}

pub fn resolve_debug_session(reference: Option<&str>) -> Result<StoredSession> {
    match reference.unwrap_or("latest") {
        "current" => {
            let id = current_session_id().ok_or(MicError::NoDiagnosticsSession)?;
            load_session(&id)
        }
        "latest" => resolve_latest_non_debug_session(),
        explicit => load_session(explicit),
    }
}

fn resolve_latest_non_debug_session() -> Result<StoredSession> {
    let mut candidate = previous_session_id()
        .or(latest_session_id()?)
        .ok_or(MicError::NoDiagnosticsSession)?;
    let current_id = current_session_id();

    loop {
        if current_id.as_deref() == Some(candidate.as_str()) {
            return Err(MicError::NoDiagnosticsSession);
        }

        let session = load_session(&candidate)?;
        if !matches!(
            session.command_name.as_deref(),
            Some("debug" | "mount-serve")
        ) {
            return Ok(session);
        }

        candidate = session
            .previous_session_id
            .clone()
            .ok_or(MicError::NoDiagnosticsSession)?;
    }
}

pub fn read_verbose_log(session: &StoredSession) -> Result<String> {
    match fs::read_to_string(&session.verbose_log_file) {
        Ok(contents) => Ok(contents),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(String::new()),
        Err(error) => Err(error.into()),
    }
}

pub fn read_request_summaries(session: &StoredSession) -> Result<Vec<RequestSummary>> {
    let har = match fs::read_to_string(&session.network_har_file) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    let root: HarRoot = serde_json::from_str(&har)?;
    Ok(root
        .log
        .entries
        .into_iter()
        .map(|entry| RequestSummary {
            started_at: entry.started_date_time,
            method: entry.request.method,
            url: entry.request.url,
            status: entry.response.status,
            duration_ms: entry.time,
            transport: entry
                .comment
                .as_deref()
                .and_then(|comment| comment.split_whitespace().next())
                .and_then(|chunk| chunk.strip_prefix("transport="))
                .unwrap_or("http")
                .to_string(),
            comment: entry.comment,
        })
        .collect())
}

pub fn read_grpc_entries(session: &StoredSession) -> Result<Vec<GrpcDebugEntry>> {
    let contents = match fs::read_to_string(&session.grpc_messages_file) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };

    let mut entries = Vec::new();
    for line in contents.lines() {
        if line.trim().is_empty() {
            continue;
        }
        entries.push(serde_json::from_str::<GrpcDebugEntry>(line)?);
    }
    Ok(entries)
}

#[derive(Clone, Copy)]
enum BodyKind {
    Json,
    Form,
    Plain,
}

fn capture_text_body_with_kind(text: &str, mime_type: &str, kind: BodyKind) -> CapturedBody {
    let sanitized = match kind {
        BodyKind::Json => sanitize_json_text(text),
        BodyKind::Form => sanitize_form_text(text),
        BodyKind::Plain => text.to_string(),
    };

    let bytes = sanitized.as_bytes();
    let truncated = bytes.len() > BODY_CAPTURE_LIMIT;
    let slice = if truncated {
        &bytes[..BODY_CAPTURE_LIMIT]
    } else {
        bytes
    };

    CapturedBody {
        mime_type: mime_type.to_string(),
        text: String::from_utf8_lossy(slice).into_owned(),
        encoding: None,
        size: bytes.len(),
        truncated,
    }
}

fn sanitize_json_text(text: &str) -> String {
    match serde_json::from_str::<Value>(text) {
        Ok(mut value) => {
            redact_json_value(&mut value);
            serde_json::to_string(&value).unwrap_or_else(|_| REDACTED.to_string())
        }
        Err(_) => text.to_string(),
    }
}

fn sanitize_form_text(text: &str) -> String {
    let mut serializer = url::form_urlencoded::Serializer::new(String::new());
    for (name, value) in url::form_urlencoded::parse(text.as_bytes()) {
        serializer.append_pair(&name, &redact_if_sensitive(&name, &value));
    }
    serializer.finish()
}

fn redact_json_value(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for (key, value) in map.iter_mut() {
                if sensitive_keys().contains(&key.to_ascii_lowercase()) {
                    *value = Value::String(REDACTED.to_string());
                } else {
                    redact_json_value(value);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                redact_json_value(item);
            }
        }
        _ => {}
    }
}

fn redact_url(url: &str) -> String {
    let Ok(mut parsed) = Url::parse(url) else {
        return url.to_string();
    };

    let query_pairs: Vec<(String, String)> = parsed
        .query_pairs()
        .map(|(name, value)| (name.to_string(), redact_if_sensitive(&name, &value)))
        .collect();
    parsed.set_query(None);
    if !query_pairs.is_empty() {
        let mut serializer = url::form_urlencoded::Serializer::new(String::new());
        for (name, value) in query_pairs {
            serializer.append_pair(&name, &value);
        }
        parsed.set_query(Some(&serializer.finish()));
    }
    parsed.to_string()
}

fn sanitize_header_value(name: &str, value: &str) -> String {
    if sensitive_header_names().contains(&name.to_ascii_lowercase()) {
        REDACTED.to_string()
    } else {
        value.to_string()
    }
}

fn redact_if_sensitive(name: &str, value: &str) -> String {
    if sensitive_keys().contains(&name.to_ascii_lowercase()) {
        REDACTED.to_string()
    } else {
        value.to_string()
    }
}

fn sensitive_header_names() -> BTreeSet<String> {
    ["authorization", "cookie", "set-cookie", "x-api-key"]
        .into_iter()
        .map(|name| name.to_string())
        .collect()
}

fn sensitive_keys() -> BTreeSet<String> {
    [
        "access_token",
        "refresh_token",
        "id_token",
        "client_secret",
        "authorization",
        "device_code",
        "user_code",
    ]
    .into_iter()
    .map(|name| name.to_string())
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capture_json_body_redacts_sensitive_fields() {
        let captured = capture_json_body(
            r#"{"access_token":"secret","nested":{"refresh_token":"refresh"},"safe":"ok"}"#,
        );

        assert!(captured.text.contains(REDACTED));
        assert!(!captured.text.contains("secret"));
        assert!(!captured.text.contains("\"refresh\""));
        assert!(captured.text.contains("\"safe\":\"ok\""));
    }

    #[test]
    fn capture_text_body_redacts_json_mime_types() {
        let captured = capture_text_body(
            r#"{"access_token":"secret","safe":"ok"}"#,
            "application/json; charset=utf-8",
        );

        assert!(captured.text.contains(REDACTED));
        assert!(!captured.text.contains("\"secret\""));
        assert!(captured.text.contains("\"safe\":\"ok\""));
    }

    #[test]
    fn create_session_writes_metadata_and_har() {
        let temp = tempfile::tempdir().expect("tempdir");
        let cwd = temp.path().join("cwd");
        fs::create_dir_all(&cwd).expect("create cwd");

        let session = create_session(
            temp.path(),
            &["hif".into(), "status".into()],
            &cwd,
            None,
            true,
            "human",
            Some("status"),
        )
        .expect("create session");

        assert!(session.info.session_file.exists());
        assert!(session.info.network_har_file.exists());
        assert!(session.info.grpc_messages_file.exists());
        assert!(temp.path().join("latest-session").exists());
        assert!(uuid::Uuid::parse_str(&session.info.id).is_ok());
    }

    #[test]
    fn network_exchange_redacts_auth_data_in_har() {
        let temp = tempfile::tempdir().expect("tempdir");
        let cwd = temp.path().join("cwd");
        fs::create_dir_all(&cwd).expect("create cwd");
        let mut session = create_session(
            temp.path(),
            &["hif".into(), "auth".into(), "login".into()],
            &cwd,
            None,
            true,
            "human",
            Some("auth"),
        )
        .expect("create session");

        session
            .append_network_exchange(NetworkExchange {
                kind: "http",
                started_at: timestamp_now(),
                duration: Duration::from_millis(12),
                method: "POST".to_string(),
                url: "https://example.com/oauth/token".to_string(),
                http_version: Some("HTTP/1.1".to_string()),
                request_headers: vec![("authorization".to_string(), REDACTED.to_string())],
                request_body: Some(capture_form_body(
                    "refresh_token=very-secret&client_id=test-client",
                )),
                response_status: 200,
                response_status_text: "OK".to_string(),
                response_headers: vec![(
                    "content-type".to_string(),
                    "application/json".to_string(),
                )],
                response_body: Some(capture_json_body(
                    r#"{"access_token":"secret","refresh_token":"other-secret"}"#,
                )),
                error: None,
            })
            .expect("append exchange");

        let har = fs::read_to_string(&session.info.network_har_file).expect("read har");
        assert!(har.contains(REDACTED));
        assert!(!har.contains("very-secret"));
        assert!(!har.contains("\"secret\""));
        assert!(!har.contains("other-secret"));
    }

    #[test]
    fn grpc_exchange_writes_message_sidecar() {
        let temp = tempfile::tempdir().expect("tempdir");
        let cwd = temp.path().join("cwd");
        fs::create_dir_all(&cwd).expect("create cwd");
        let mut session = create_session(
            temp.path(),
            &["hif".into(), "org".into(), "list".into()],
            &cwd,
            None,
            true,
            "human",
            Some("org"),
        )
        .expect("create session");

        session
            .append_grpc_exchange(GrpcExchange {
                started_at: timestamp_now(),
                duration: Duration::from_millis(8),
                method: "/hif.v1.OrganizationService/ListOrganizations".to_string(),
                url: "https://example.com/hif.v1.OrganizationService/ListOrganizations".to_string(),
                http_version: Some("HTTP/2".to_string()),
                http_status: 200,
                request_headers: vec![("authorization".to_string(), REDACTED.to_string())],
                response_headers: vec![("grpc-status".to_string(), "0".to_string())],
                grpc_status: Some("0".to_string()),
                grpc_message: None,
                request_body: vec![0, 0, 0, 0, 3, 8, 1, 16],
                response_body: Some(vec![0, 0, 0, 0, 2, 8, 1]),
                error: None,
            })
            .expect("append grpc exchange");

        let entries = read_grpc_entries(&StoredSession {
            id: session.info.id.clone(),
            started_at: session.metadata.started_at.clone(),
            ended_at: session.metadata.ended_at.clone(),
            pid: session.metadata.pid,
            argv: session.metadata.argv.clone(),
            cwd: session.metadata.cwd.clone(),
            requested_cwd: session.metadata.requested_cwd.clone(),
            verbose: session.metadata.verbose,
            output_mode: session.metadata.output_mode.clone(),
            exit_code: session.metadata.exit_code,
            previous_session_id: session.metadata.previous_session_id.clone(),
            command_name: session.metadata.command_name.clone(),
            dir: session.info.dir.clone(),
            session_file: session.info.session_file.clone(),
            verbose_log_file: session.info.verbose_log_file.clone(),
            network_har_file: session.info.network_har_file.clone(),
            grpc_messages_file: session.info.grpc_messages_file.clone(),
        })
        .expect("read grpc entries");

        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].request_messages.len(), 1);
        assert_eq!(entries[0].response_messages.len(), 1);
        assert_eq!(entries[0].grpc_status.as_deref(), Some("0"));
    }
}
