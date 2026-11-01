use std::ffi::{c_char, CStr};
use std::sync::atomic::AtomicBool;
use crate::transfer::{self, ConnectionParams};

#[repr(C)]
pub struct SftpTransferConfig {
    pub host: *const c_char,
    pub port: u16,
    pub username: *const c_char,
    pub password: *const c_char,
    pub jump_host: *const c_char,
    pub jump_port: u16,
    pub jump_username: *const c_char,
    pub jump_password: *const c_char,
    pub local_path: *const c_char,
    pub remote_path: *const c_char,
}

pub type ProgressCallback = extern "C" fn(transferred: i64, total: i64);

#[no_mangle]
pub extern "C" fn nexus_sftp_is_available() -> i32 {
    1
}

unsafe fn c_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        None
    } else {
        CStr::from_ptr(ptr).to_str().ok()
    }
}

#[no_mangle]
pub extern "C" fn nexus_sftp_upload(
    config: *const SftpTransferConfig,
    callback: Option<ProgressCallback>,
    cancel_flag: *const AtomicBool,
) -> i32 {
    if config.is_null() {
        return -1;
    }

    let cfg = unsafe { &*config };
    let host = match unsafe { c_to_str(cfg.host) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    let username = match unsafe { c_to_str(cfg.username) } {
        Some(s) => s,
        None => return -1,
    };
    let password = unsafe { c_to_str(cfg.password) }.unwrap_or("");
    let local_path = match unsafe { c_to_str(cfg.local_path) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    let remote_path = match unsafe { c_to_str(cfg.remote_path) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };

    let jump_host = unsafe { c_to_str(cfg.jump_host) };
    let jump_username = unsafe { c_to_str(cfg.jump_username) };
    let jump_password = unsafe { c_to_str(cfg.jump_password) };

    let cancel = if cancel_flag.is_null() {
        None
    } else {
        unsafe { Some(&*cancel_flag) }
    };

    let params = ConnectionParams {
        host,
        port: cfg.port,
        username,
        password,
        jump_host,
        jump_port: cfg.jump_port,
        jump_username,
        jump_password,
    };

    let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
        Ok(rt) => rt,
        Err(_) => return -99,
    };

    let progress_wrapper = callback.map(|cb| {
        move |transferred: i64, total: i64| {
            cb(transferred, total);
        }
    });

    match rt.block_on(transfer::upload_file(&params, local_path, remote_path, progress_wrapper, cancel)) {
        Ok(_) => 0,
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("cancelled") {
                -6
            } else if msg.contains("auth") || msg.contains("Auth") {
                -3
            } else {
                -2
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn nexus_sftp_download(
    config: *const SftpTransferConfig,
    callback: Option<ProgressCallback>,
    cancel_flag: *const AtomicBool,
) -> i32 {
    if config.is_null() {
        return -1;
    }

    let cfg = unsafe { &*config };
    let host = match unsafe { c_to_str(cfg.host) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    let username = match unsafe { c_to_str(cfg.username) } {
        Some(s) => s,
        None => return -1,
    };
    let password = unsafe { c_to_str(cfg.password) }.unwrap_or("");
    let remote_path = match unsafe { c_to_str(cfg.remote_path) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    let local_path = match unsafe { c_to_str(cfg.local_path) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };

    let jump_host = unsafe { c_to_str(cfg.jump_host) };
    let jump_username = unsafe { c_to_str(cfg.jump_username) };
    let jump_password = unsafe { c_to_str(cfg.jump_password) };

    let cancel = if cancel_flag.is_null() {
        None
    } else {
        unsafe { Some(&*cancel_flag) }
    };

    let params = ConnectionParams {
        host,
        port: cfg.port,
        username,
        password,
        jump_host,
        jump_port: cfg.jump_port,
        jump_username,
        jump_password,
    };

    let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
        Ok(rt) => rt,
        Err(_) => return -99,
    };

    let progress_wrapper = callback.map(|cb| {
        move |transferred: i64, total: i64| {
            cb(transferred, total);
        }
    });

    match rt.block_on(transfer::download_file(&params, remote_path, local_path, progress_wrapper, cancel)) {
        Ok(_) => 0,
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("cancelled") {
                -6
            } else if msg.contains("auth") || msg.contains("Auth") {
                -3
            } else {
                -2
            }
        }
    }
}
