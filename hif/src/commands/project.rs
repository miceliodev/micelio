//! Project management commands.

use crate::cli::{parse_project_ref, ProjectCommand, ProjectSubcommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};

/// Run the project command.
pub async fn run(cmd: ProjectCommand) -> Result<()> {
    match cmd.command {
        ProjectSubcommand::List { org } => list(&org).await,
        ProjectSubcommand::Create {
            project,
            name,
            description,
        } => {
            let (org, handle) = parse_project_ref(&project).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    project
                ))
            })?;
            create(org, handle, &name, description.as_deref()).await
        }
        ProjectSubcommand::Info { project } => {
            let (org, handle) = parse_project_ref(&project).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    project
                ))
            })?;
            info(org, handle).await
        }
        ProjectSubcommand::Update {
            project,
            name,
            description,
        } => {
            let (org, handle) = parse_project_ref(&project).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    project
                ))
            })?;
            update(org, handle, name.as_deref(), description.as_deref()).await
        }
        ProjectSubcommand::Delete { project } => {
            let (org, handle) = parse_project_ref(&project).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    project
                ))
            })?;
            delete(org, handle).await
        }
    }
}

/// List projects in an organization.
async fn list(organization: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, organization.as_bytes());

    let response = client
        .unary_call(
            "/micelio.projects.v1.ProjectService/ListProjects",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    let mut pos = 0;
    while pos < response.len() {
        if let Some((field_number, _, data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                let (name, handle) = parse_project(data);
                println!("{}/{} - {}", organization, handle, name);
            }
        }
    }

    Ok(())
}

/// Create a new project.
async fn create(
    organization: &str,
    handle: &str,
    name: &str,
    description: Option<&str>,
) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, organization.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());
    write_length_delimited(&mut request, 3, name.as_bytes());
    if let Some(desc) = description {
        write_length_delimited(&mut request, 4, desc.as_bytes());
    }

    let _ = client
        .unary_call(
            "/micelio.projects.v1.ProjectService/CreateProject",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Project created: {}/{}", organization, handle);
    Ok(())
}

/// Get project details.
async fn info(organization: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, organization.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let response = client
        .unary_call(
            "/micelio.projects.v1.ProjectService/GetProject",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    let (name, handle, description) = parse_project_details(&response);

    println!("Project: {}", name);
    println!("Handle: {}/{}", organization, handle);
    if !description.is_empty() {
        println!("Description: {}", description);
    }

    Ok(())
}

/// Update a project.
async fn update(
    organization: &str,
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
    write_length_delimited(&mut request, 1, organization.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());
    if let Some(n) = name {
        write_length_delimited(&mut request, 3, n.as_bytes());
    }
    if let Some(d) = description {
        write_length_delimited(&mut request, 4, d.as_bytes());
    }

    let _ = client
        .unary_call(
            "/micelio.projects.v1.ProjectService/UpdateProject",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Project updated.");
    Ok(())
}

/// Delete a project.
async fn delete(organization: &str, handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, organization.as_bytes());
    write_length_delimited(&mut request, 2, handle.as_bytes());

    let _ = client
        .unary_call(
            "/micelio.projects.v1.ProjectService/DeleteProject",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    println!("Project deleted: {}/{}", organization, handle);
    Ok(())
}

/// Parse project from protobuf.
fn parse_project(data: &[u8]) -> (String, String) {
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

/// Parse project details from protobuf.
fn parse_project_details(data: &[u8]) -> (String, String, String) {
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
