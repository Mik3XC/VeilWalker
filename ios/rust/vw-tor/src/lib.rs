//! C ABI for VeilWalker iOS (see include/vw_tor.h).
//!
//! Unlike Android's JNI crate there is no SOCKS port: Swift hands whole requests to `vw_http`, which
//! opens an Arti stream and speaks HTTP/1.1 over it. One code path, no proxy config, and `.onion`
//! names never reach the system resolver.
//!
//! All calls block; Swift calls them off the main thread. Errors are per calling thread: after a call
//! returns -1, `vw_last_error` on the same thread says why.

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use arti_client::config::TorClientConfigBuilder;
use arti_client::TorClient;
use http_body_util::{BodyExt, Full};
use hyper::body::Bytes;
use hyper_util::rt::TokioIo;
use once_cell::sync::Lazy;
use tokio::runtime::{Handle, Runtime};
use tor_rtcompat::PreferredRuntime;

struct Running {
    rt: Runtime,
    client: Arc<TorClient<PreferredRuntime>>,
}

static STATE: Lazy<Mutex<Option<Running>>> = Lazy::new(|| Mutex::new(None));

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

fn set_error(msg: impl ToString) {
    LAST_ERROR.with(|e| *e.borrow_mut() = msg.to_string());
}

fn panic_message(p: Box<dyn std::any::Any + Send>) -> String {
    p.downcast_ref::<String>()
        .cloned()
        .or_else(|| p.downcast_ref::<&str>().map(|s| s.to_string()))
        .unwrap_or_else(|| "unknown panic".into())
}

/// Runs `f`, turning errors and panics into -1 plus a thread-local message. A panic must never unwind into Swift.
fn guarded(f: impl FnOnce() -> Result<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(format!("{e:#}"));
            -1
        }
        Err(p) => {
            set_error(format!("panic: {}", panic_message(p)));
            -1
        }
    }
}

unsafe fn str_arg<'a>(p: *const c_char, name: &str) -> Result<&'a str> {
    if p.is_null() {
        bail!("{name} is null");
    }
    CStr::from_ptr(p).to_str().with_context(|| format!("{name} is not UTF-8"))
}

/// Bootstraps Arti with its state and cache in the given directories (Application Support, excluded from
/// backup, so later starts reuse the cached consensus). Returns 0 when connected, -1 on error or timeout.
/// Already running: returns 0 immediately.
#[no_mangle]
pub unsafe extern "C" fn vw_tor_start(state_dir: *const c_char, cache_dir: *const c_char, timeout_ms: u32) -> i32 {
    guarded(|| {
        let state_dir = str_arg(state_dir, "state_dir")?.to_owned();
        let cache_dir = str_arg(cache_dir, "cache_dir")?.to_owned();
        // Arti's TLS is rustls 0.23, which needs a process-wide crypto provider picked explicitly.
        let _ = rustls::crypto::ring::default_provider().install_default();

        let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
        if guard.is_some() {
            return Ok(());
        }
        let rt = Runtime::new().context("tokio runtime")?;
        let budget = Duration::from_millis(timeout_ms.into());
        let client = rt
            .block_on(async { tokio::time::timeout(budget, boot(state_dir, cache_dir)).await })
            .map_err(|_| anyhow::anyhow!("bootstrap timed out after {} ms", timeout_ms))??;
        *guard = Some(Running { rt, client });
        Ok(())
    })
}

async fn boot(state_dir: String, cache_dir: String) -> Result<Arc<TorClient<PreferredRuntime>>> {
    let mut builder = TorClientConfigBuilder::from_directories(state_dir, cache_dir);
    // The app container's parent directories aren't owned by the app, which Arti's permission
    // checker (fs-mistrust) rejects. The iOS sandbox already isolates the container.
    builder.storage().permissions().dangerously_trust_everyone();
    let config = builder.build()?;
    Ok(TorClient::create_bootstrapped(config).await?.into())
}

/// Tears down Arti. Safe to call when not running.
#[no_mangle]
pub extern "C" fn vw_tor_stop() {
    let running = STATE.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(r) = running {
        drop(r.client);
        r.rt.shutdown_background();
    }
}

/// 1 if Arti is bootstrapped and running, else 0.
#[no_mangle]
pub extern "C" fn vw_tor_is_running() -> i32 {
    STATE.lock().unwrap_or_else(|e| e.into_inner()).is_some() as i32
}

/// Why the last call on this thread returned -1. Free with `vw_string_free`.
#[no_mangle]
pub extern "C" fn vw_last_error() -> *mut c_char {
    let msg = LAST_ERROR.with(|e| e.borrow().replace('\0', ""));
    CString::new(msg).unwrap_or_default().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn vw_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

#[repr(C)]
pub struct VwHttpResponse {
    pub status: i32,
    pub body: *mut u8,
    pub body_len: usize,
}

/// One HTTP/1.1 request over Tor: plain `http://<name>.onion` (the onion service encrypts end to end), or `https://`
/// to the few clearnet hosts in TLS_HOSTS, with TLS through the exit. Anything else is refused: plain HTTP to a
/// clearnet host would be readable by the exit relay. `headers` is "Name: value" lines separated by '\n' (may be null or empty).
/// On success fills `out` (free with `vw_http_response_free`) and returns 0; any HTTP status counts as success.
#[no_mangle]
pub unsafe extern "C" fn vw_http(
    method: *const c_char,
    url: *const c_char,
    headers: *const c_char,
    body: *const u8,
    body_len: usize,
    timeout_ms: u32,
    out: *mut VwHttpResponse,
) -> i32 {
    guarded(|| {
        if out.is_null() {
            bail!("out is null");
        }
        let method = str_arg(method, "method")?.to_owned();
        let url = str_arg(url, "url")?.to_owned();
        let headers = if headers.is_null() { String::new() } else { str_arg(headers, "headers")?.to_owned() };
        let body = if body.is_null() || body_len == 0 {
            Vec::new()
        } else {
            std::slice::from_raw_parts(body, body_len).to_vec()
        };

        let (handle, client): (Handle, Arc<TorClient<PreferredRuntime>>) = {
            let guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
            let r = guard.as_ref().context("tor is not running")?;
            (r.rt.handle().clone(), r.client.clone())
        };
        let budget = Duration::from_millis(timeout_ms.into());
        let (status, bytes) = handle
            .block_on(async { tokio::time::timeout(budget, http(client, &method, &url, &headers, body)).await })
            .map_err(|_| anyhow::anyhow!("request timed out after {} ms", timeout_ms))??;

        let boxed = bytes.into_boxed_slice();
        let len = boxed.len();
        *out = VwHttpResponse { status: status.into(), body: Box::into_raw(boxed) as *mut u8, body_len: len };
        Ok(())
    })
}

#[no_mangle]
pub unsafe extern "C" fn vw_http_response_free(r: *mut VwHttpResponse) {
    if r.is_null() || (*r).body.is_null() {
        return;
    }
    let slice = std::ptr::slice_from_raw_parts_mut((*r).body, (*r).body_len);
    drop(Box::from_raw(slice));
    (*r).body = std::ptr::null_mut();
    (*r).body_len = 0;
}

/// Clearnet hosts `vw_http` may reach, always over TLS through a Tor exit. Only what the app needs: the US
/// National Weather Service for the opt-in temperature.
const TLS_HOSTS: &[&str] = &["api.weather.gov"];

async fn http(
    client: Arc<TorClient<PreferredRuntime>>,
    method: &str,
    url: &str,
    headers: &str,
    body: Vec<u8>,
) -> Result<(u16, Vec<u8>)> {
    let uri: hyper::Uri = url.parse().context("bad url")?;
    let host = uri.host().context("url has no host")?.to_owned();
    let path = uri.path_and_query().map(|p| p.as_str()).unwrap_or("/").to_owned();
    match uri.scheme_str() {
        Some("http") if host.ends_with(".onion") => {
            let stream = client.connect((host.as_str(), uri.port_u16().unwrap_or(80))).await.context("tor connect to onion service")?;
            send(TokioIo::new(stream), method, &path, &host, headers, body).await
        }
        Some("https") if TLS_HOSTS.contains(&host.as_str()) => {
            let stream = client.connect((host.as_str(), uri.port_u16().unwrap_or(443))).await.context("tor connect through exit")?;
            let name = rustls::pki_types::ServerName::try_from(host.clone()).context("bad tls server name")?;
            let tls = tls_connector().connect(name, stream).await.context("tls handshake")?;
            send(TokioIo::new(tls), method, &path, &host, headers, body).await
        }
        _ => bail!("vw_http speaks http to .onion hosts and https to {:?} only", TLS_HOSTS),
    }
}

fn tls_connector() -> tokio_rustls::TlsConnector {
    static CONFIG: Lazy<Arc<rustls::ClientConfig>> = Lazy::new(|| {
        let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
        let config = rustls::ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .expect("ring supports the default TLS versions")
            .with_root_certificates(roots)
            .with_no_client_auth();
        Arc::new(config)
    });
    tokio_rustls::TlsConnector::from(CONFIG.clone())
}

async fn send<T>(io: T, method: &str, path: &str, host: &str, headers: &str, body: Vec<u8>) -> Result<(u16, Vec<u8>)>
where
    T: hyper::rt::Read + hyper::rt::Write + Unpin + Send + 'static,
{
    let (mut sender, conn) = hyper::client::conn::http1::handshake(io).await?;
    tokio::spawn(async move {
        let _ = conn.await;
    });
    let mut req = hyper::Request::builder().method(method).uri(path).header("host", host);
    for line in headers.lines() {
        if let Some((name, value)) = line.split_once(':') {
            req = req.header(name.trim(), value.trim());
        }
    }
    let res = sender.send_request(req.body(Full::new(Bytes::from(body)))?).await?;
    let status = res.status().as_u16();
    let bytes = res.into_body().collect().await?.to_bytes();
    Ok((status, bytes.to_vec()))
}
