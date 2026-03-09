//! Repository management commands.

use crate::cli::{parse_repository_ref, RepositoryCommand, RepositorySubcommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;

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
    write_length_delimited(&mut request, 1, account.as_bytes());

    let response = client
        .unary_call_authed(
            "/micelio.repositories.v1.RepositoryService/ListRepositories",
            &request,
        )
        .await?;

    let mut pos = 0;
    let mut repositories = Vec::new();
    while pos < response.len() {
        if let Some((field_number, _, data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                let (name, handle) = parse_repository(data);
                repositories.push(serde_json::json!({
                    "account": account,
                    "handle": handle,
                    "name": name
                }));
            }
        }
    }

    if output::use_json() {
        output::print_ok(
            "repository.list",
            serde_json::json!({
                "account": account,
                "repositories": repositories
            }),
        )?;
    } else {
        for repository in repositories {
            println!(
                "{}/{} - {}",
                repository["account"].as_str().unwrap_or_default(),
                repository["handle"].as_str().unwrap_or_default(),
                repository["name"].as_str().unwrap_or_default()
            );
        }
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
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());
    write_length_delimited(&mut request, 3, name.as_bytes());
    if let Some(desc) = description {
        write_length_delimited(&mut request, 4, desc.as_bytes());
    }

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.RepositoryService/CreateRepository",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.create",
            serde_json::json!({
                "account": account,
                "repository": handle,
                "name": name,
                "description": description
            }),
        )?;
    } else {
        println!("Repository created: {}/{}", account, handle);
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
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let response = client
        .unary_call_authed(
            "/micelio.repositories.v1.RepositoryService/GetRepository",
            &request,
        )
        .await?;

    let (name, handle, description) = parse_repository_details(&response);

    if output::use_json() {
        output::print_ok(
            "repository.info",
            serde_json::json!({
                "account": account,
                "handle": handle,
                "name": name,
                "description": description
            }),
        )?;
    } else {
        println!("Repository: {}", name);
        println!("Handle: {}/{}", account, handle);
        if !description.is_empty() {
            println!("Description: {}", description);
        }
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
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());
    if let Some(n) = name {
        write_length_delimited(&mut request, 3, n.as_bytes());
    }
    if let Some(d) = description {
        write_length_delimited(&mut request, 4, d.as_bytes());
    }

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.RepositoryService/UpdateRepository",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.update",
            serde_json::json!({
                "account": account,
                "repository": handle,
                "name": name,
                "description": description
            }),
        )?;
    } else {
        println!("Repository updated.");
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
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let _ = client
        .unary_call_authed(
            "/micelio.repositories.v1.RepositoryService/DeleteRepository",
            &request,
        )
        .await?;

    if output::use_json() {
        output::print_ok(
            "repository.delete",
            serde_json::json!({
                "account": account,
                "repository": handle
            }),
        )?;
    } else {
        println!("Repository deleted: {}/{}", account, handle);
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
                1 => handle = read_string(field_data),
                2 => name = read_string(field_data),
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
            match field_number {
                1 => handle = read_string(field_data),
                2 => name = read_string(field_data),
                3 => description = read_string(field_data),
                _ => {}
            }
        }
    }

    (name, handle, description)
}
