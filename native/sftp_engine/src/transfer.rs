use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use russh::keys::PublicKeyOrCertificate;
use russh_sftp::client::SftpSession;

const CHUNK_SIZE: usize = 256 * 1024; // 256 KB buffer for high-throughput streaming

struct ClientHandler;

impl russh::client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        Ok(true)
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

async fn open_sftp_session(params: &ConnectionParams<'_>) -> Result<SftpSession, Box<dyn std::error::Error + Send + Sync>> {
    let mut config = russh::client::Config::default();
    config.window_size = 4 * 1024 * 1024; // 4MB sliding window for maximum transfer throughput
    let config = Arc::new(config);

    if let (Some(j_host), Some(j_user), Some(j_pass)) = (params.jump_host, params.jump_username, params.jump_password) {
        if !j_host.is_empty() {
            let mut jump_session = russh::client::connect(config.clone(), (j_host, params.jump_port), ClientHandler).await?;
            let _ = jump_session.authenticate_password(j_user, j_pass).await?;
            let channel = jump_session.channel_open_direct_tcpip(params.host, params.port as u32, "127.0.0.1", 22).await?;
            let mut target_session = russh::client::connect_stream(config.clone(), channel.into_stream(), ClientHandler).await?;
            let _ = target_session.authenticate_password(params.username, params.password).await?;
            let sftp_chan = target_session.channel_open_session().await?;
            sftp_chan.request_subsystem(true, "sftp").await?;
            let sftp = SftpSession::new(sftp_chan.into_stream()).await?;
            return Ok(sftp);
        }
    }

    let mut session = russh::client::connect(config, (params.host, params.port), ClientHandler).await?;
    let _ = session.authenticate_password(params.username, params.password).await?;
    let sftp_chan = session.channel_open_session().await?;
    sftp_chan.request_subsystem(true, "sftp").await?;
    let sftp = SftpSession::new(sftp_chan.into_stream()).await?;
    Ok(sftp)
}

pub async fn upload_file<F>(
    params: &ConnectionParams<'_>,
    local_path: &str,
    remote_path: &str,
    progress: Option<F>,
    cancel_flag: Option<&AtomicBool>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    F: Fn(i64, i64) + Send + Sync + 'static,
{
    let sftp = open_sftp_session(params).await?;
    let mut local_file = tokio::fs::File::open(local_path).await?;
    let total_bytes = local_file.metadata().await?.len() as i64;

    let mut remote_file = sftp.create(remote_path).await?;
    let mut buf = vec![0u8; CHUNK_SIZE];
    let mut transferred: i64 = 0;

    loop {
        if let Some(flag) = cancel_flag {
            if flag.load(Ordering::Relaxed) {
                return Err("Transfer cancelled by user".into());
            }
        }

        let n = local_file.read(&mut buf).await?;
        if n == 0 {
            break;
        }

        remote_file.write_all(&buf[..n]).await?;
        transferred += n as i64;

        if let Some(ref cb) = progress {
            cb(transferred, total_bytes);
        }
    }

    remote_file.flush().await?;
    Ok(())
}

pub async fn download_file<F>(
    params: &ConnectionParams<'_>,
    remote_path: &str,
    local_path: &str,
    progress: Option<F>,
    cancel_flag: Option<&AtomicBool>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    F: Fn(i64, i64) + Send + Sync + 'static,
{
    let sftp = open_sftp_session(params).await?;
    let meta = sftp.metadata(remote_path).await?;
    let total_bytes = meta.size.unwrap_or(0) as i64;

    let mut remote_file = sftp.open(remote_path).await?;

    if let Some(parent) = std::path::Path::new(local_path).parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let mut local_file = tokio::fs::File::create(local_path).await?;

    let mut buf = vec![0u8; CHUNK_SIZE];
    let mut transferred: i64 = 0;

    loop {
        if let Some(flag) = cancel_flag {
            if flag.load(Ordering::Relaxed) {
                return Err("Transfer cancelled by user".into());
            }
        }

        let n = remote_file.read(&mut buf).await?;
        if n == 0 {
            break;
        }

        local_file.write_all(&buf[..n]).await?;
        transferred += n as i64;

        if let Some(ref cb) = progress {
            cb(transferred, total_bytes);
        }
    }

    local_file.flush().await?;
    Ok(())
}
