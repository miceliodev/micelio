//! Grep command - search repository content with remote index and local fallback.

use crate::cli::{parse_repository_ref, GrepCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output::{self, CliOutput};
use crate::workspace::{parse_position, PositionOrLatest};
use regex::Regex;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Serialize, Default)]
pub(crate) struct IdentityOutput {
    id: String,
    acct: String,
    handle: String,
    instance: String,
    kind: String,
}

#[derive(Serialize)]
pub(crate) struct SearchMatchOutput {
    path: String,
    line: u32,
    column: u32,
    snippet: String,
    session_id: String,
    attributed_to: IdentityOutput,
    revision_hash: Vec<u8>,
}

#[derive(Serialize)]
pub(crate) struct LocalSearchMatchOutput {
    path: String,
    line: usize,
    column: usize,
    snippet: String,
}

#[derive(Serialize)]
pub(crate) struct GrepOutput<T>
where
    T: Serialize,
{
    source: &'static str,
    repository: String,
    query: String,
    matches: Vec<T>,
    total: u64,
}

impl CliOutput for pb::TextQueryMatch {
    type Model = SearchMatchOutput;

    fn into_cli_output(self) -> Self::Model {
        SearchMatchOutput {
            path: self.path,
            line: self.line,
            column: self.column,
            snippet: self.snippet,
            session_id: self.session_id,
            attributed_to: self.attributed_to.map(identity_output).unwrap_or_default(),
            revision_hash: self.revision_hash,
        }
    }
}

/// Run the grep command.
pub async fn run(cmd: GrepCommand) -> Result<()> {
    let (org, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let position = if let Some(ref raw) = cmd.position {
        match parse_position(raw) {
            Some(PositionOrLatest::Revision(value)) => Some(value),
            Some(PositionOrLatest::Latest) => None,
            None => {
                return Err(MicError::Other(
                    "Invalid --position value; expected revision hash".to_string(),
                ))
            }
        }
    } else {
        None
    };

    let request = pb::TextQueryRequest {
        repository: Some(repository_ref(org, repository)),
        query: cmd.query.clone(),
        at_revision_hash: position.unwrap_or_default(),
        path_prefix: cmd.path.clone().unwrap_or_default(),
        path_glob: String::new(),
        regex: cmd.regex,
        case_sensitive: cmd.case_sensitive,
        language_hint: String::new(),
        limit: normalize_limit(cmd.limit),
        offset: 0,
        page_token: Vec::new(),
    };

    let remote =
        call::<_, pb::TextQueryResponse>(&client, "/hif.v1.SearchService/QueryText", &request)
            .await;

    match remote {
        Ok(response) => {
            if output::use_json() {
                output::print_ok(
                    "grep",
                    GrepOutput {
                        source: "remote",
                        repository: cmd.repository,
                        query: cmd.query,
                        matches: response.matches.into_cli_output(),
                        total: response.total,
                    },
                )
            } else {
                for m in response.matches {
                    println!("{}:{}:{}: {}", m.path, m.line, m.column, m.snippet);
                }
                Ok(())
            }
        }
        Err(remote_error) if cmd.local => {
            match local_grep(
                &cmd.query,
                cmd.path.as_deref(),
                cmd.regex,
                cmd.case_sensitive,
                cmd.limit,
                output::use_json(),
            ) {
                Ok(local_matches) => {
                    if output::use_json() {
                        output::print_ok(
                            "grep",
                            GrepOutput {
                                source: "local",
                                repository: cmd.repository,
                                query: cmd.query,
                                total: local_matches.len() as u64,
                                matches: local_matches,
                            },
                        )
                    } else {
                        Ok(())
                    }
                }
                Err(local_error) => Err(MicError::Other(format!(
                    "Remote grep failed ({}); local fallback failed ({})",
                    remote_error, local_error
                ))),
            }
        }
        Err(remote_error) => Err(remote_error),
    }
}

fn local_grep(
    query: &str,
    path_prefix: Option<&str>,
    use_regex: bool,
    case_sensitive: bool,
    limit: u32,
    json_output: bool,
) -> Result<Vec<LocalSearchMatchOutput>> {
    let regex =
        if use_regex {
            Some(Regex::new(query).map_err(|error| {
                MicError::Other(format!("Invalid regex '{}': {}", query, error))
            })?)
        } else {
            None
        };

    let mut files = Vec::new();
    collect_files(&std::env::current_dir()?, &mut files)?;

    let mut printed = 0u32;
    let max = normalize_limit(limit);
    let normalized_query = if case_sensitive {
        query.to_string()
    } else {
        query.to_lowercase()
    };
    let mut matches = Vec::new();

    for file in files {
        let display_path = display_path(&file);

        if let Some(prefix) = path_prefix {
            if !display_path.starts_with(prefix) {
                continue;
            }
        }

        let content = match fs::read(&file) {
            Ok(content) => content,
            Err(_) => continue,
        };

        let text = match String::from_utf8(content) {
            Ok(text) => text,
            Err(_) => continue,
        };

        for (line_number, line) in text.lines().enumerate() {
            if printed >= max {
                return Ok(matches);
            }

            let maybe_column = match &regex {
                Some(regex) => regex.find(line).map(|m| m.start() + 1),
                None => {
                    if case_sensitive {
                        line.find(&normalized_query).map(|idx| idx + 1)
                    } else {
                        line.to_lowercase()
                            .find(&normalized_query)
                            .map(|idx| idx + 1)
                    }
                }
            };

            if let Some(column) = maybe_column {
                if !json_output {
                    println!("{}:{}:{}: {}", display_path, line_number + 1, column, line);
                }
                matches.push(LocalSearchMatchOutput {
                    path: display_path.clone(),
                    line: line_number + 1,
                    column,
                    snippet: line.to_string(),
                });
                printed += 1;
            }
        }
    }

    Ok(matches)
}

fn collect_files(root: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    if !root.is_dir() {
        return Ok(());
    }

    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();
        let file_name = file_name.to_string_lossy();

        if path.is_dir() {
            if file_name == ".git" || file_name == ".hif" || file_name == "target" {
                continue;
            }
            collect_files(&path, files)?;
        } else if path.is_file() {
            files.push(path);
        }
    }

    Ok(())
}

fn display_path(path: &Path) -> String {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    path.strip_prefix(&cwd)
        .map(|relative| relative.to_string_lossy().replace('\\', "/"))
        .unwrap_or_else(|_| path.to_string_lossy().replace('\\', "/"))
}

fn normalize_limit(limit: u32) -> u32 {
    if limit == 0 {
        20
    } else if limit > 500 {
        500
    } else {
        limit
    }
}

fn identity_output(identity: pb::IdentityRef) -> IdentityOutput {
    IdentityOutput {
        id: identity.id,
        acct: identity.acct,
        handle: identity.handle,
        instance: identity.instance,
        kind: identity.kind,
    }
}
