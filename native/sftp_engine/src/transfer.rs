use std::future::Future;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use russh::client::{Handle, KeyboardInteractiveAuthResponse};
use russh::keys::PublicKeyOrCertificate;
use russh_sftp::client::SftpSession;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const CHUNK_SIZE: usize = 256 * 1024;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
/// How often pause/cancel flags are polled while waiting.
const CONTROL_POLL: Duration = Duration::from_millis(100);
/// Minimum gap between progress callbacks (the last one is always sent).
const PROGRESS_INTERVAL: Duration = Duration::from_millis(100);
/// Upper bound for closing/removing a file after a failed or cancelled transfer.
const CLOSE_TIMEOUT: Duration = Duration::from_secs(1);

pub struct ClientHandler;

impl russh::client::Handler for ClientHandler {
    type Error = russh::Error;

    // Same trust model as the Dart client (StrictHostKeyChecking=no).
    async fn check_server_key(
        &mut self,
        _server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

/// Shared with Dart: two bytes in native memory the UI isolate writes and the
/// engine polls. Non-zero means set.
#[repr(C)]
pub struct TransferControl {
    pub cancel: AtomicU8,
    pub pause: AtomicU8,
}

#[derive(Debug)]
pub enum EngineError {
    InvalidArgs(String),
    Connect(String),
    Auth(String),
    SftpUnavailable(String),
    Io(String),
    Cancelled,
}

impl EngineError {
    pub fn code(&self) -> i32 {
        match self {
            EngineError::InvalidArgs(_) => -1,
            EngineError::Io(_) => -2,
            EngineError::Auth(_) => -3,
            EngineError::Connect(_) => -4,
            EngineError::SftpUnavailable(_) => -5,
            EngineError::Cancelled => -6,
        }
    }

    pub fn message(&self) -> String {
        match self {
            EngineError::InvalidArgs(m)
            | EngineError::Connect(m)
            | EngineError::Auth(m)
            | EngineError::SftpUnavailable(m)
            | EngineError::Io(m) => m.clone(),
            EngineError::Cancelled => "Transfer cancelled by user".to_string(),
        }
    }
}

impl From<std::io::Error> for EngineError {
    fn from(e: std::io::Error) -> Self {
        EngineError::Io(e.to_string())
    }
}

impl From<russh_sftp::client::error::Error> for EngineError {
    fn from(e: russh_sftp::client::error::Error) -> Self {
        EngineError::Io(format!("SFTP: {e}"))
    }
}

pub struct ConnectionParams<'a> {
    pub host: &'a str,
    pub port: u16,
    pub username: &'a str,
    pub password: &'a str,
    pub jump_host: Option<&'a str>,
    pub jump_port: u16,
    pub jump_username: Option<&'a str>,
    pub jump_password: Option<&'a str>,
}

/// Pause/cancel checks for one transfer. With no control block attached the
/// transfer can be neither paused nor cancelled.
pub struct Control<'a>(pub Option<&'a TransferControl>);

impl Control<'_> {
    fn is_cancelled(&self) -> bool {
        self.0.map_or(false, |c| c.cancel.load(Ordering::Acquire) != 0)
    }

    fn is_paused(&self) -> bool {
        self.0.map_or(false, |c| c.pause.load(Ordering::Acquire) != 0)
    }

    /// Returns once neither paused nor cancelled; errors on cancel. While
    /// paused nothing is read, so the SSH window closes and the server stops.
    async fn checkpoint(&self) -> Result<(), EngineError> {
        loop {
            if self.is_cancelled() {
                return Err(EngineError::Cancelled);
            }
            if !self.is_paused() {
                return Ok(());
            }
            tokio::time::sleep(CONTROL_POLL).await;
        }
    }

    async fn cancelled(&self) {
        if self.0.is_none() {
            std::future::pending::<()>().await;
        }
        while !self.is_cancelled() {
            tokio::time::sleep(CONTROL_POLL).await;
        }
    }

    /// Runs [fut] but gives up as soon as the transfer is cancelled, so a
    /// stalled peer cannot keep a cancelled transfer alive.
    async fn run<T>(&self, fut: impl Future<Output = T>) -> Result<T, EngineError> {
        tokio::select! {
            r = fut => Ok(r),
            _ = self.cancelled() => Err(EngineError::Cancelled),
        }
    }
}

struct Progress<'a> {
    callback: &'a mut dyn FnMut(i64, i64),
    total: i64,
    last: Option<Instant>,
}

impl Progress<'_> {
    fn report(&mut self, transferred: i64, force: bool) {
        let now = Instant::now();
        if !force {
            if let Some(last) = self.last {
                if now.duration_since(last) < PROGRESS_INTERVAL {
                    return;
                }
            }
        }
        self.last = Some(now);
        (self.callback)(transferred, self.total.max(transferred));
    }
}

async fn authenticate(
    handle: &mut Handle<ClientHandler>,
    user: &str,
    password: &str,
) -> Result<(), EngineError> {
    let res = handle
        .authenticate_password(user, password)
        .await
        .map_err(|e| EngineError::Auth(format!("Authentication failed for {user}: {e}")))?;
    if res.success() {
        return Ok(());
    }

    // Many appliances only offer keyboard-interactive; answer every prompt
    // with the password, as the Dart client does.
    let mut resp = handle
        .authenticate_keyboard_interactive_start(user, None::<String>)
        .await
        .map_err(|e| EngineError::Auth(format!("Authentication failed for {user}: {e}")))?;
    for _ in 0..8 {
        match resp {
            KeyboardInteractiveAuthResponse::Success => return Ok(()),
            KeyboardInteractiveAuthResponse::Failure { .. } => break,
            KeyboardInteractiveAuthResponse::InfoRequest { prompts, .. } => {
                let answers = prompts.iter().map(|_| password.to_string()).collect();
                resp = handle
                    .authenticate_keyboard_interactive_respond(answers)
                    .await
                    .map_err(|e| {
                        EngineError::Auth(format!("Authentication failed for {user}: {e}"))
                    })?;
            }
        }
    }
    Err(EngineError::Auth(format!(
        "Authentication failed for {user} (password and keyboard-interactive rejected)"
    )))
}

fn client_config() -> Arc<russh::client::Config> {
    let mut config = russh::client::Config::default();
    config.window_size = 4 * 1024 * 1024;
    // Keeps the connection alive between files and while a transfer is paused.
    config.keepalive_interval = Some(Duration::from_secs(15));
    config.keepalive_max = 4;
    Arc::new(config)
}

async fn with_timeout<T, E: std::fmt::Display>(
    what: &str,
    fut: impl Future<Output = Result<T, E>>,
) -> Result<T, EngineError> {
    match tokio::time::timeout(CONNECT_TIMEOUT, fut).await {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(e)) => Err(EngineError::Connect(format!("{what}: {e}"))),
        Err(_) => Err(EngineError::Connect(format!(
            "{what}: timed out after {}s",
            CONNECT_TIMEOUT.as_secs()
        ))),
    }
}

/// One SSH connection (optionally through a jump host) with an SFTP session,
/// reused for every file of a job.
pub struct Connection {
    _jump: Option<Handle<ClientHandler>>,
    session: Handle<ClientHandler>,
    sftp: SftpSession,
}

impl Connection {
    pub async fn open(params: &ConnectionParams<'_>) -> Result<Connection, EngineError> {
        let config = client_config();
        let target = format!("{}:{}", params.host, params.port);

        let mut jump = None;
        let mut session = match (params.jump_host, params.jump_username) {
            (Some(j_host), Some(j_user)) if !j_host.is_empty() => {
                let j_pass = params.jump_password.unwrap_or("");
                let mut jump_session = with_timeout(
                    &format!("Connect to jump host {j_host}:{}", params.jump_port),
                    russh::client::connect(config.clone(), (j_host, params.jump_port), ClientHandler),
                )
                .await?;
                authenticate(&mut jump_session, j_user, j_pass).await?;
                let channel = with_timeout(
                    &format!("Open tunnel to {target}"),
                    jump_session.channel_open_direct_tcpip(
                        params.host,
                        params.port as u32,
                        "127.0.0.1",
                        22,
                    ),
                )
                .await?;
                let s = with_timeout(
                    &format!("Connect to {target}"),
                    russh::client::connect_stream(config.clone(), channel.into_stream(), ClientHandler),
                )
                .await?;
                jump = Some(jump_session);
                s
            }
            _ => {
                with_timeout(
                    &format!("Connect to {target}"),
                    russh::client::connect(config.clone(), (params.host, params.port), ClientHandler),
                )
                .await?
            }
        };

        authenticate(&mut session, params.username, params.password).await?;

        let chan = session
            .channel_open_session()
            .await
            .map_err(|e| EngineError::SftpUnavailable(format!("Open session channel: {e}")))?;
        chan.request_subsystem(true, "sftp")
            .await
            .map_err(|e| EngineError::SftpUnavailable(format!("SFTP subsystem: {e}")))?;
        let sftp = SftpSession::new(chan.into_stream())
            .await
            .map_err(|e| EngineError::SftpUnavailable(format!("SFTP init: {e}")))?;

        Ok(Connection { _jump: jump, session, sftp })
    }

    /// Downloads [remote] to [local]. On any failure (including cancel) the
    /// partial local file is removed.
    pub async fn download(
        &self,
        remote: &str,
        local: &str,
        on_progress: &mut dyn FnMut(i64, i64),
        ctl: &Control<'_>,
    ) -> Result<(), EngineError> {
        ctl.checkpoint().await?;
        let total = ctl.run(self.sftp.metadata(remote)).await??.size.unwrap_or(0) as i64;
        let mut remote_file = ctl.run(self.sftp.open(remote)).await??;

        if let Some(parent) = std::path::Path::new(local).parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let mut local_file = tokio::fs::File::create(local).await?;
        let mut progress = Progress { callback: on_progress, total, last: None };
        progress.report(0, true);

        let result: Result<i64, EngineError> = async {
            let mut buf = vec![0u8; CHUNK_SIZE];
            let mut transferred: i64 = 0;
            loop {
                ctl.checkpoint().await?;
                let n = ctl.run(remote_file.read(&mut buf)).await??;
                if n == 0 {
                    break;
                }
                local_file.write_all(&buf[..n]).await?;
                transferred += n as i64;
                progress.report(transferred, false);
            }
            local_file.flush().await?;
            if total > 0 && transferred != total {
                return Err(EngineError::Io(format!(
                    "Download incomplete: received {transferred} of {total} bytes for {remote}"
                )));
            }
            Ok(transferred)
        }
        .await;

        // After a cancel the server may still be answering read-ahead
        // requests; do not let closing the handle hold the caller up.
        let _ = tokio::time::timeout(CLOSE_TIMEOUT, remote_file.shutdown()).await;
        drop(local_file);
        match result {
            Ok(transferred) => {
                progress.report(transferred, true);
                Ok(())
            }
            Err(e) => {
                let _ = tokio::fs::remove_file(local).await;
                Err(e)
            }
        }
    }

    /// Uploads [local] to [remote] (created/truncated). On failure the partial
    /// remote file is removed.
    pub async fn upload(
        &self,
        local: &str,
        remote: &str,
        on_progress: &mut dyn FnMut(i64, i64),
        ctl: &Control<'_>,
    ) -> Result<(), EngineError> {
        ctl.checkpoint().await?;
        let mut local_file = tokio::fs::File::open(local).await?;
        let total = local_file.metadata().await?.len() as i64;
        let mut remote_file = ctl.run(self.sftp.create(remote)).await??;
        let mut progress = Progress { callback: on_progress, total, last: None };
        progress.report(0, true);

        let result: Result<i64, EngineError> = async {
            let mut buf = vec![0u8; CHUNK_SIZE];
            let mut transferred: i64 = 0;
            loop {
                ctl.checkpoint().await?;
                let n = local_file.read(&mut buf).await?;
                if n == 0 {
                    break;
                }
                ctl.run(remote_file.write_all(&buf[..n])).await??;
                transferred += n as i64;
                progress.report(transferred, false);
            }
            ctl.run(remote_file.flush()).await??;
            Ok(transferred)
        }
        .await;

        match result {
            Ok(transferred) => {
                remote_file.shutdown().await?;
                progress.report(transferred, true);
                Ok(())
            }
            Err(e) => {
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, async {
                    let _ = remote_file.shutdown().await;
                    let _ = self.sftp.remove_file(remote).await;
                })
                .await;
                Err(e)
            }
        }
    }

    pub async fn close(self) {
        let _ = self.sftp.close().await;
        let _ = self
            .session
            .disconnect(russh::Disconnect::ByApplication, "", "en")
            .await;
        if let Some(jump) = self._jump {
            let _ = jump.disconnect(russh::Disconnect::ByApplication, "", "en").await;
        }
    }
}
