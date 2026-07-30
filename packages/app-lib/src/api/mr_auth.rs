use crate::state::BbsmcCredentials;
use serde::Deserialize;

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum BbsmcAuthFlow {
    SignIn,
    SignUp,
}

#[tracing::instrument]
pub fn authenticate_begin_flow(flow: BbsmcAuthFlow) -> &'static str {
    match flow {
        BbsmcAuthFlow::SignIn => crate::state::get_login_url(),
        BbsmcAuthFlow::SignUp => crate::state::get_signup_url(),
    }
}

#[tracing::instrument]
pub async fn authenticate_finish_flow(
    code: &str,
) -> crate::Result<BbsmcCredentials> {
    let state = crate::State::get().await?;

    let creds = crate::state::finish_login_flow(
        code,
        &state.api_semaphore,
        &state.pool,
    )
    .await?;

    creds.upsert(&state.pool).await?;
    state.friends_socket.disconnect().await?;
    state
        .friends_socket
        .connect(&state.pool, &state.api_semaphore, &state.process_manager)
        .await?;

    Ok(creds)
}

#[tracing::instrument]
pub async fn logout() -> crate::Result<()> {
    let state = crate::State::get().await?;
    let current = BbsmcCredentials::get_active(&state.pool).await?;

    if let Some(current) = current {
        BbsmcCredentials::remove(&current.user_id, &state.pool).await?;
    }
    state.friends_socket.disconnect().await?;

    Ok(())
}

#[tracing::instrument]
pub async fn get_credentials() -> crate::Result<Option<BbsmcCredentials>> {
    let state = crate::State::get().await?;
    let current =
        BbsmcCredentials::get_and_refresh(&state.pool, &state.api_semaphore)
            .await?;
    if current.is_none() {
        state.friends_socket.disconnect().await?;
    }

    Ok(current)
}
