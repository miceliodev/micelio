//! Repository management commands.

use crate::cli::{parse_repository_ref, RepositoryCommand, RepositorySubcommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct RepositoryListEntryOutput {
    account: String,
    handle: String,
    name: String,
}

#[derive(Serialize)]
pub(crate) struct RepositoryListOutput {
    account: String,
    repositories: Vec<RepositoryListEntryOutput>,
}

#[derive(Serialize)]
pub(crate) struct RepositoryCreateOutput {
    account: String,
    repository: String,
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct RepositoryInfoOutput {
    account: String,
    handle: String,
    name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    description: String,
}

#[derive(Serialize)]
pub(crate) struct RepositoryUpdateOutput {
    account: String,
    repository: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct RepositoryDeleteOutput {
    account: String,
    repository: String,
}

/// Run the repository command.
pub async fn run(cmd: RepositoryCommand) -> Result<()> {
    match cmd.command {
        RepositorySubcommand::List { account } => list(&account).await,
        RepositorySubcommand::Create {
            repository,
            name,
            description,
        } => {
            let (org, handle) = parse_repository_ref(&repository).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    repository
                ))
            })?;
            create(org, handle, &name, description.as_deref()).await
        }
        RepositorySubcommand::Info { repository } => {
            let (org, handle) = parse_repository_ref(&repository).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    repository
                ))
            })?;
            info(org, handle).await
        }
        RepositorySubcommand::Update {
            repository,
            name,
            description,
        } => {
            let (org, handle) = parse_repository_ref(&repository).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    repository
                ))
            })?;
            update(org, handle, name.as_deref(), description.as_deref()).await
        }
        RepositorySubcommand::Delete { repository } => {
            let (org, handle) = parse_repository_ref(&repository).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    repository
                ))
            })?;
            delete(org, handle).await
        }
    }
}

/// List repositories in an account.
async fn list(account: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 2, account.as_bytes());

    let response = client
        .unary_call_authed(
            "/micelio.repositories.v1.ProjectService/ListProjects",
            &request,
        )
        .await?;

    let mut pos = 0;
    let mut repositories = Vec::new();
    while pos < response.len() {
        if let Some((field_number, _, data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                let (name, handle) = parse_repository(data);
                repositories.push(RepositoryListEntryOutput {
                    account: account.to_string(),
                    handle,
                    name,
                });
            }
        }
    }

    if output::use_json() {
        output::print_ok(
            "repository.list",
            RepositoryListOutput {
                account: account.to_string(),
                repositories,
            },
        )?;
    } else {
        let repository_count = repositories.len();
        for repository in repositories {
            output::ui_line(format!(
                "{}/{} - {}",
                repository.account, repository.handle, repository.name
            ));
        }
        output::set_success_message(format!(
            "Listed {} repositories in '{}'.",
            repository_count, account
        ));
    }

    Ok(())
}

/// Create a new repository.
async fn create(account: &str, handle: &str, name: &str, description: Option<&str>) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 2, account.as_bytes());
    write_length_delimited(&mut request, 3, handle.as_bytes());
    write_length_delimited(&mut request, 4, name.as_bytes());
    if let Some(desc) = description {
        write_length_delimited(&mut request, 5, desc.as_bytes());
    }

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.ProjectService/CreateProject",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.create",
            RepositoryCreateOutput {
                account: account.to_string(),
                repository: handle.to_string(),
                name: name.to_string(),
                description: description.map(str::to_string),
            },
        )?;
    } else {
        output::set_success_message(format!("Created repository '{}/{}'.", account, handle));
    }
    Ok(())
}

/// Get repository details.
async fn info(account: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 2, account.as_bytes());
    write_length_delimited(&mut request, 3, handle.as_bytes());

    let response = client
        .unary_call_authed(
            "/micelio.repositories.v1.ProjectService/GetProject",
            &request,
        )
        .await?;

    let (name, handle, description) = parse_repository_details(&response);

    if output::use_json() {
        output::print_ok(
            "repository.info",
            RepositoryInfoOutput {
                account: account.to_string(),
                handle,
                name,
                description,
            },
        )?;
    } else {
        output::ui_line(format!("Repository: {}", name));
        output::ui_line(format!("Handle: {}/{}", account, handle));
        if !description.is_empty() {
            output::ui_line(format!("Description: {}", description));
        }
        output::set_success_message("Loaded repository details.");
    }

    Ok(())
}

/// Update a repository.
async fn update(
    account: &str,
    handle: &str,
    name: Option<&str>,
    description: Option<&str>,
) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 2, account.as_bytes());
    write_length_delimited(&mut request, 3, handle.as_bytes());
    if let Some(n) = name {
        write_length_delimited(&mut request, 5, n.as_bytes());
    }
    if let Some(d) = description {
        write_length_delimited(&mut request, 6, d.as_bytes());
    }

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.ProjectService/UpdateProject",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.update",
            RepositoryUpdateOutput {
                account: account.to_string(),
                repository: handle.to_string(),
                name: name.map(str::to_string),
                description: description.map(str::to_string),
            },
        )?;
    } else {
        output::set_success_message(format!("Updated repository '{}/{}'.", account, handle));
    }
    Ok(())
}

/// Delete a repository.
async fn delete(account: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 2, account.as_bytes());
    write_length_delimited(&mut request, 3, handle.as_bytes());

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.ProjectService/DeleteProject",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.delete",
            RepositoryDeleteOutput {
                account: account.to_string(),
                repository: handle.to_string(),
            },
        )?;
    } else {
        output::set_success_message(format!("Deleted repository '{}/{}'.", account, handle));
    }
    Ok(())
}

/// Parse repository from protobuf.
fn parse_repository(data: &[u8]) -> (String, String) {
    let mut pos = 0;
    let mut name = String::new();
    let mut handle = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                4 => handle = read_string(field_data),
                5 => name = read_string(field_data),
                _ => {}
            }
        }
    }

    (name, handle)
}

/// Parse repository details from protobuf.
fn parse_repository_details(data: &[u8]) -> (String, String, String) {
    let mut pos = 0;
    let mut name = String::new();
    let mut handle = String::new();
    let mut description = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            if field_number == 1 {
                let mut project_pos = 0;

                while project_pos < field_data.len() {
                    if let Some((project_field_number, _, project_field_data)) =
                        read_field(field_data, &mut project_pos)
                    {
                        match project_field_number {
                            4 => handle = read_string(project_field_data),
                            5 => name = read_string(project_field_data),
                            6 => description = read_string(project_field_data),
                            _ => {}
                        }
                    }
                }
            }
        }
    }

    (name, handle, description)
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_repository_list_requires_auth() {
        assert_output_snapshot(
            &["repository", "list", "acme"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }

    #[test]
    fn ui_snapshot_repository_create_requires_auth() {
        assert_output_snapshot(
            &["repository", "create", "acme/repo", "Repo"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }

    #[test]
    fn ui_snapshot_repository_info_requires_auth() {
        assert_output_snapshot(
            &["repository", "info", "acme/repo"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }

    #[test]
    fn ui_snapshot_repository_update_requires_auth() {
        assert_output_snapshot(
            &["repository", "update", "acme/repo", "--name", "Renamed"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }

    #[test]
    fn ui_snapshot_repository_delete_requires_auth() {
        assert_output_snapshot(
            &["repository", "delete", "acme/repo"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }
}
