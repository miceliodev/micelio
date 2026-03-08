//! Repository management commands.

use crate::cli::{parse_repository_ref, RepositoryCommand, RepositorySubcommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};

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
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());

    let response = client
        .unary_call(
            "/micelio.repositories.v1.RepositoryService/ListRepositories",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    let mut pos = 0;
    while pos < response.len() {
        if let Some((field_number, _, data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                let (name, handle) = parse_repository(data);
                println!("{}/{} - {}", account, handle, name);
            }
        }
    }

    Ok(())
}

/// Create a new repository.
async fn create(account: &str, handle: &str, name: &str, description: Option<&str>) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
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
        .unary_call(
            "/micelio.repositories.v1.RepositoryService/CreateRepository",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Repository created: {}/{}", account, handle);
    Ok(())
}

/// Get repository details.
async fn info(account: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let response = client
        .unary_call(
            "/micelio.repositories.v1.RepositoryService/GetRepository",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    let (name, handle, description) = parse_repository_details(&response);

    println!("Repository: {}", name);
    println!("Handle: {}/{}", account, handle);
    if !description.is_empty() {
        println!("Description: {}", description);
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
    let tokens = config::require_tokens()?;
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
        .unary_call(
            "/micelio.repositories.v1.RepositoryService/UpdateRepository",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Repository updated.");
    Ok(())
}

/// Delete a repository.
async fn delete(account: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let _ = client
        .unary_call(
            "/micelio.repositories.v1.RepositoryService/DeleteRepository",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Repository deleted: {}/{}", account, handle);
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
