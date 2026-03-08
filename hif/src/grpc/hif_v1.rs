//! Typed helpers for `hif.v1` RPCs.

use crate::config;
use crate::error::{MicError, Result};
use crate::grpc::GrpcClient;
use prost::Message;

pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/hif.v1.rs"));
}

/// Decode the authenticated user id from a bearer token payload.
pub fn user_id_from_token(access_token: &str) -> String {
    config::token_subject(access_token).unwrap_or_default()
}

/// Build a repository reference message.
pub fn repository_ref(org: &str, repository: &str) -> pb::RepositoryRef {
    pb::RepositoryRef {
        organization_handle: org.to_string(),
        repository_handle: repository.to_string(),
    }
}

/// Perform a typed unary call against a hif v1 endpoint.
pub async fn call<Req, Res>(
    client: &GrpcClient,
    access_token: &str,
    method: &str,
    request: &Req,
) -> Result<Res>
where
    Req: Message,
    Res: Message + Default,
{
    let response = client
        .unary_call(method, &request.encode_to_vec(), Some(access_token))
        .await?;

    Res::decode(response.as_slice()).map_err(|error| {
        MicError::GrpcError(format!("Failed to decode {} response: {}", method, error))
    })
}
