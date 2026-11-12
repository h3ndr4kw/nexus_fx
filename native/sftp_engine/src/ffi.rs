//! C ABI used by the Dart `RustSftpBridge`.
//!
//! Lifecycle: `nexus_sftp_connect` opens one SSH/SFTP connection and returns
//! an engine handle; any number of `nexus_sftp_engine_download/upload` calls
//! reuse it (one at a time); `nexus_sftp_disconnect` frees it. Transfers poll
//! a caller-owned `TransferControl` (cancel/pause bytes) and report progress
//! through a callback invoked on the calling thread.

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};

use crate::transfer::{self, ConnectionParams, Control, EngineError, TransferControl};

/// Bumped whenever the C ABI changes, so Dart can refuse a stale DLL.
pub const API_VERSION: i32 = 4;

const PANIC_CODE: i32 = -99;

#[repr(C)]
pub struct SftpConnectConfig {
    pub host: *const c_char,
    pub port: u16,
    pub username: *const c_char,
    pub password: *const c_char,
    pub jump_host: *const c_char,
    pub jump_port: u16,
    pub jump_username: *const c_char,
    pub jump_password: *const c_char,
    /// Newline-separated `SHA256:...` fingerprints the target may present.
    /// Empty or null rejects every key.
    pub host_keys: *const c_char,
    /// Same for the jump host.
    pub jump_host_keys: *const c_char,
    /// Optional private key files (absolute paths) and passphrases.
    pub key_path: *const c_char,
    pub key_passphrase: *const c_char,
    pub jump_key_path: *const c_char,
    pub jump_key_passphrase: *const c_char,
}

pub type ProgressCallback = extern "C" fn(transferred: i64, total: i64);

pub struct Engine {
    rt: tokio::runtime::Runtime,
    conn: Option<transfer::Connection>,
}

#[no_mangle]
pub extern "C" fn nexus_sftp_is_available() -> i32 {
    1
}

#[no_mangle]
pub extern "C" fn nexus_sftp_api_version() -> i32 {
    API_VERSION
}

unsafe fn c_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        None
    } else {
        CStr::from_ptr(ptr).to_str().ok()
    }
}

/// Copies [msg] into the caller's buffer as a NUL-terminated UTF-8 string,
/// truncated to fit.
unsafe fn write_error(buf: *mut c_char, len: usize, msg: &str) {
    if buf.is_null() || len == 0 {
        return;
    }
    let bytes = msg.as_bytes();
    let mut n = bytes.len().min(len - 1);
    while n > 0 && !msg.is_char_boundary(n) {
        n -= 1;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
    *buf.add(n) = 0;
}

unsafe fn fail(buf: *mut c_char, len: usize, e: &EngineError) -> i32 {
    write_error(buf, len, &e.message());
    e.code()
}

/// Opens a connection. Returns null on failure, with the error code in
/// `*out_code` and a message in `err_buf`.
#[no_mangle]
pub extern "C" fn nexus_sftp_connect(
    config: *const SftpConnectConfig,
    err_buf: *mut c_char,
    err_len: usize,
    out_code: *mut i32,
) -> *mut Engine {
    let result = catch_unwind(AssertUnwindSafe(|| unsafe {
        if config.is_null() {
            return Err(EngineError::InvalidArgs("missing config".into()));
        }
        let cfg = &*config;
        let host = match c_to_str(cfg.host) {
            Some(s) if !s.is_empty() => s,
            _ => return Err(EngineError::InvalidArgs("missing host".into())),
        };
        let username = c_to_str(cfg.username)
            .ok_or_else(|| EngineError::InvalidArgs("missing username".into()))?;
        let params = ConnectionParams {
            host,
            port: cfg.port,
            username,
            password: c_to_str(cfg.password).unwrap_or(""),
            jump_host: c_to_str(cfg.jump_host),
            jump_port: cfg.jump_port,
            jump_username: c_to_str(cfg.jump_username),
            jump_password: c_to_str(cfg.jump_password),
            host_keys: transfer::parse_fingerprints(c_to_str(cfg.host_keys)),
            jump_host_keys: transfer::parse_fingerprints(c_to_str(cfg.jump_host_keys)),
            key: transfer::KeyFile::from_parts(c_to_str(cfg.key_path), c_to_str(cfg.key_passphrase)),
            jump_key: transfer::KeyFile::from_parts(
                c_to_str(cfg.jump_key_path),
                c_to_str(cfg.jump_key_passphrase),
            ),
        };

        // One worker thread drives russh's background tasks (keepalive,
        // window updates) even between calls; transfers themselves run on the
        // calling thread via block_on, so callbacks arrive on that thread.
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .map_err(|e| EngineError::Io(format!("runtime: {e}")))?;
        let conn = rt.block_on(transfer::Connection::open(&params))?;
        Ok(Box::into_raw(Box::new(Engine { rt, conn: Some(conn) })))
    }));

    let (ptr, code) = match result {
        Ok(Ok(ptr)) => (ptr, 0),
        Ok(Err(e)) => (std::ptr::null_mut(), unsafe { fail(err_buf, err_len, &e) }),
        Err(_) => {
            unsafe { write_error(err_buf, err_len, "native engine panicked while connecting") };
            (std::ptr::null_mut(), PANIC_CODE)
        }
    };
    if !out_code.is_null() {
        unsafe { *out_code = code };
    }
    ptr
}

fn run_transfer(
    engine: *mut Engine,
    a: *const c_char,
    b: *const c_char,
    callback: Option<ProgressCallback>,
    control: *const TransferControl,
    err_buf: *mut c_char,
    err_len: usize,
    upload: bool,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| unsafe {
        if engine.is_null() {
            return Err(EngineError::InvalidArgs("engine is closed".into()));
        }
        let engine = &mut *engine;
        let conn = engine
            .conn
            .as_ref()
            .ok_or_else(|| EngineError::InvalidArgs("engine is closed".into()))?;
        let a = match c_to_str(a) {
            Some(s) if !s.is_empty() => s,
            _ => return Err(EngineError::InvalidArgs("missing source path".into())),
        };
        let b = match c_to_str(b) {
            Some(s) if !s.is_empty() => s,
            _ => return Err(EngineError::InvalidArgs("missing destination path".into())),
        };
        let ctl = Control(if control.is_null() { None } else { Some(&*control) });
        let mut on_progress = |t: i64, total: i64| {
            if let Some(cb) = callback {
                cb(t, total);
            }
        };
        if upload {
            engine.rt.block_on(conn.upload(a, b, &mut on_progress, &ctl))
        } else {
            engine.rt.block_on(conn.download(a, b, &mut on_progress, &ctl))
        }
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => unsafe { fail(err_buf, err_len, &e) },
        Err(_) => {
            unsafe { write_error(err_buf, err_len, "native engine panicked during transfer") };
            PANIC_CODE
        }
    }
}

/// Downloads `remote_path` to `local_path`. Returns 0 on success, -6 when
/// cancelled, another negative code on error (message in `err_buf`).
#[no_mangle]
pub extern "C" fn nexus_sftp_engine_download(
    engine: *mut Engine,
    remote_path: *const c_char,
    local_path: *const c_char,
    callback: Option<ProgressCallback>,
    control: *const TransferControl,
    err_buf: *mut c_char,
    err_len: usize,
) -> i32 {
    run_transfer(engine, remote_path, local_path, callback, control, err_buf, err_len, false)
}

/// Uploads `local_path` to `remote_path`. Same return codes as download.
#[no_mangle]
pub extern "C" fn nexus_sftp_engine_upload(
    engine: *mut Engine,
    local_path: *const c_char,
    remote_path: *const c_char,
    callback: Option<ProgressCallback>,
    control: *const TransferControl,
    err_buf: *mut c_char,
    err_len: usize,
) -> i32 {
    run_transfer(engine, local_path, remote_path, callback, control, err_buf, err_len, true)
}

/// Closes the connection and frees the engine. Safe to call with null.
#[no_mangle]
pub extern "C" fn nexus_sftp_disconnect(engine: *mut Engine) {
    if engine.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let mut engine = Box::from_raw(engine);
        if let Some(conn) = engine.conn.take() {
            let _ = engine.rt.block_on(async {
                tokio::time::timeout(std::time::Duration::from_secs(3), conn.close()).await
            });
        }
        let Engine { rt, .. } = *engine;
        rt.shutdown_background();
    }));
}
