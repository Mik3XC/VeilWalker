//! JNI bridge: `org.trailbound.core.net.arti.ArtiNative`.
//!
//! `start(stateDir, cacheDir) -> port` bootstraps Arti and serves a minimal SOCKS5 (CONNECT only,
//! no auth, hostname addressing) listener on 127.0.0.1. Hostnames are resolved *inside* Tor, so
//! OkHttp must not resolve DNS locally (it doesn't when given a SOCKS proxy).

use std::sync::Mutex;
use std::time::Duration;

use anyhow::{bail, Result};
use arti_client::config::TorClientConfigBuilder;
use arti_client::TorClient;
use jni::objects::{JClass, JString};
use jni::sys::jint;
use jni::JNIEnv;
use once_cell::sync::Lazy;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Runtime;
use tokio::sync::oneshot;
use tor_rtcompat::PreferredRuntime;

struct Running {
    _rt: Runtime,
    shutdown: Option<oneshot::Sender<()>>,
    port: u16,
}

static STATE: Lazy<Mutex<Option<Running>>> = Lazy::new(|| Mutex::new(None));
static LAST_ERROR: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

/// Bootstrap budget. Enforced here because a Kotlin timeout can't interrupt this blocking JNI call.
const BOOT_TIMEOUT: Duration = Duration::from_secs(45);

extern "C" {
    fn __android_log_write(prio: i32, tag: *const std::ffi::c_char, text: *const std::ffi::c_char) -> i32;
}

/// Android drops stderr, so panics and errors go to logcat under "VeilWalker/Arti".
fn logcat(msg: &str) {
    #[cfg(target_os = "android")]
    {
        let tag = std::ffi::CString::new("VeilWalker/Arti").unwrap();
        let text = std::ffi::CString::new(msg.replace('\0', "")).unwrap();
        unsafe { __android_log_write(6 /* ERROR */, tag.as_ptr(), text.as_ptr()) };
    }
    #[cfg(not(target_os = "android"))]
    eprintln!("{msg}");
}

fn fail(msg: impl ToString) -> jint {
    let msg = msg.to_string();
    logcat(&msg);
    *LAST_ERROR.lock().unwrap() = msg;
    -1
}

#[no_mangle]
pub extern "system" fn Java_org_trailbound_core_net_arti_ArtiNative_start(
    mut env: JNIEnv,
    _class: JClass,
    state_dir: JString,
    cache_dir: JString,
) -> jint {
    std::panic::set_hook(Box::new(|info| logcat(&format!("panic: {info}"))));
    let (state_dir, cache_dir) = match (env.get_string(&state_dir), env.get_string(&cache_dir)) {
        (Ok(a), Ok(b)) => (String::from(a), String::from(b)),
        _ => return fail("bad directory arguments"),
    };
    // A panic must never unwind into the JVM: turn it into an error the app can show.
    match std::panic::catch_unwind(|| start_inner(state_dir, cache_dir)) {
        Ok(port) => port,
        Err(p) => {
            let msg = p.downcast_ref::<String>().cloned()
                .or_else(|| p.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_else(|| "unknown panic".into());
            fail(format!("panic: {msg}"))
        }
    }
}

fn start_inner(state_dir: String, cache_dir: String) -> jint {
    // Arti's TLS is rustls 0.23, which needs a process-wide crypto provider picked explicitly.
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(r) = guard.as_ref() {
        return r.port as jint;
    }
    let rt = match Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return fail(format!("tokio runtime: {e}")),
    };
    let (tx, rx) = oneshot::channel();
    let port = match rt.block_on(async { tokio::time::timeout(BOOT_TIMEOUT, boot(state_dir, cache_dir, rx)).await }) {
        Ok(Ok(p)) => p,
        Ok(Err(e)) => return fail(format!("{e:#}")),
        Err(_) => return fail("bootstrap timed out after 45 s"),
    };
    LAST_ERROR.lock().unwrap().clear();
    *guard = Some(Running { _rt: rt, shutdown: Some(tx), port });
    port as jint
}

#[no_mangle]
pub extern "system" fn Java_org_trailbound_core_net_arti_ArtiNative_stop(_env: JNIEnv, _class: JClass) {
    if let Some(mut r) = STATE.lock().unwrap().take() {
        if let Some(tx) = r.shutdown.take() {
            let _ = tx.send(());
        }
        // Dropping the runtime tears down Arti and the listener.
    }
}

/// Why the last `start` returned -1, for logs and the Tor status line.
#[no_mangle]
pub extern "system" fn Java_org_trailbound_core_net_arti_ArtiNative_lastError<'a>(
    env: JNIEnv<'a>,
    _class: JClass<'a>,
) -> JString<'a> {
    let msg = LAST_ERROR.lock().unwrap().clone();
    env.new_string(msg).unwrap_or_default()
}

async fn boot(state_dir: String, cache_dir: String, mut shutdown: oneshot::Receiver<()>) -> Result<u16> {
    let mut builder = TorClientConfigBuilder::from_directories(state_dir, cache_dir);
    // Android app dirs sit under /data/user/0, whose parents Arti's permission checker (fs-mistrust)
    // rejects. The app sandbox already isolates these dirs, so the check adds nothing here.
    builder.storage().permissions().dangerously_trust_everyone();
    let config = builder.build()?;
    let client = TorClient::create_bootstrapped(config).await?;

    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();

    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = &mut shutdown => break,
                accepted = listener.accept() => {
                    let Ok((sock, _)) = accepted else { continue };
                    let client = client.clone();
                    tokio::spawn(async move { let _ = socks5(sock, client).await; });
                }
            }
        }
    });
    Ok(port)
}

/// Minimal RFC 1928 server: no-auth, CONNECT, domain or IPv4 address.
async fn socks5(mut s: TcpStream, tor: std::sync::Arc<TorClient<PreferredRuntime>>) -> Result<()> {
    let mut hdr = [0u8; 2];
    s.read_exact(&mut hdr).await?;
    if hdr[0] != 5 {
        bail!("not socks5");
    }
    let mut methods = vec![0u8; hdr[1] as usize];
    s.read_exact(&mut methods).await?;
    s.write_all(&[5, 0]).await?;

    let mut req = [0u8; 4];
    s.read_exact(&mut req).await?;
    if req[1] != 1 {
        s.write_all(&[5, 7, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
        bail!("only CONNECT supported");
    }
    let host = match req[3] {
        1 => {
            let mut ip = [0u8; 4];
            s.read_exact(&mut ip).await?;
            std::net::Ipv4Addr::from(ip).to_string()
        }
        3 => {
            let len = s.read_u8().await? as usize;
            let mut name = vec![0u8; len];
            s.read_exact(&mut name).await?;
            String::from_utf8(name)?
        }
        _ => {
            s.write_all(&[5, 8, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
            bail!("unsupported address type");
        }
    };
    let port = s.read_u16().await?;

    match tor.connect((host.as_str(), port)).await {
        Ok(mut stream) => {
            s.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
            tokio::io::copy_bidirectional(&mut s, &mut stream).await?;
        }
        Err(e) => {
            // Surface Arti's reason (descriptor not found, circuit timeout, ...) instead of a bare "host unreachable".
            // The target is only noted as onion/clearnet so no destination ends up in logs.
            let kind = if host.ends_with(".onion") { "onion" } else { "clearnet" };
            logcat(&format!("connect to {kind} target failed: {e}"));
            s.write_all(&[5, 4, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
        }
    }
    Ok(())
}
