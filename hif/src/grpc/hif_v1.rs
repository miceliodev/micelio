//! Typed helpers for `hif.v1` RPCs.

use crate::error::{MicError, Result};
use crate::grpc::GrpcClient;
use prost::Message;

pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/hif.v1.rs"));
}

/// Build a repository reference message.
pub fn repository_ref(account: &str, repository: &str) -> pb::RepositoryRef {
    pb::RepositoryRef {
        account_handle: account.to_string(),
        repository_handle: repository.to_string(),
    }
}

/// Perform a typed unary call against a hif v1 endpoint.
pub async fn call<Req, Res>(client: &GrpcClient, method: &str, request: &Req) -> Result<Res>
where
    Req: Message,
    Res: Message + Default,
{
    let tokens = crate::config::require_tokens()?;
    let response = client
        .unary_call(method, &request.encode_to_vec(), Some(&tokens.access_token))
        .await?;

    Res::decode(response.as_slice()).map_err(|error| {
        MicError::GrpcError(format!("Failed to decode {} response: {}", method, error))
    })
}

/// Perform a typed unary call against a hif v1 endpoint, using authentication
/// when valid credentials are available and falling back to anonymous access
/// otherwise.
pub async fn call_optional_auth<Req, Res>(
    client: &GrpcClient,
    method: &str,
    request: &Req,
) -> Result<Res>
where
    Req: Message,
    Res: Message + Default,
{
    let auth_token = match crate::config::require_tokens() {
        Ok(tokens) => Some(tokens.access_token),
        Err(MicError::NotAuthenticated)
        | Err(MicError::TokenExpired)
        | Err(MicError::InvalidTokens)
        | Err(MicError::RefreshFailed(_)) => {
            crate::diagnostics::log_info(format!(
                "calling {} without stored authentication",
                method
            ));
            None
        }
        Err(error) => return Err(error),
    };

    let response = client
        .unary_call(method, &request.encode_to_vec(), auth_token.as_deref())
        .await?;

    Res::decode(response.as_slice()).map_err(|error| {
        MicError::GrpcError(format!("Failed to decode {} response: {}", method, error))
    })
}
