//! Organization management commands.

use crate::cli::{OrgCommand, OrgSubcommand};
use crate::config::Config;
use crate::error::Result;
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct OrgListOutput {
    organizations: Vec<String>,
}

#[derive(Serialize)]
pub(crate) struct OrgInfoOutput {
    name: String,
    handle: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    description: String,
}

/// Run the org command.
pub async fn run(cmd: OrgCommand) -> Result<()> {
    match cmd.command {
        OrgSubcommand::List => list().await,
        OrgSubcommand::Info { org } => info(&org).await,
    }
}

/// List organizations.
async fn list() -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    // Empty request for list
    let request = Vec::new();

    let response = client
        .unary_call_authed(
            "/micelio.organizations.v1.OrganizationService/ListOrganizations",
            &request,
        )
        .await?;

    // Parse response (simplified)
    let mut pos = 0;
    let mut organizations = Vec::new();
    while pos < response.len() {
        if let Some((field_number, _, data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                organizations.push(parse_organization(data));
            }
        }
    }

    if output::use_json() {
        output::print_ok("org.list", OrgListOutput { organizations })?;
    } else {
        for org in organizations {
            println!("{}", org);
        }
    }

    Ok(())
}

/// Get organization details.
async fn info(handle: &str) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    // Encode request
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, handle.as_bytes());

    let response = client
        .unary_call_authed(
            "/micelio.organizations.v1.OrganizationService/GetOrganization",
            &request,
        )
        .await?;

    // Parse response
    let (name, handle, description) = parse_organization_details(&response);

    if output::use_json() {
        output::print_ok(
            "org.info",
            OrgInfoOutput {
                name,
                handle,
                description,
            },
        )?;
    } else {
        println!("Organization: {}", name);
        println!("Handle: {}", handle);
        if !description.is_empty() {
            println!("Description: {}", description);
        }
    }

    Ok(())
}

/// Parse organization from protobuf.
fn parse_organization(data: &[u8]) -> String {
    let mut pos = 0;
    let mut name = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            if field_number == 2 {
                // name field
                name = read_string(field_data);
            }
        }
    }

    name
}

/// Parse organization details from protobuf.
fn parse_organization_details(data: &[u8]) -> (String, String, String) {
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
