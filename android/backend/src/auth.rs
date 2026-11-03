//! Request auth with no accounts: every request is signed by the device's Ed25519 key.
//!
//! Headers:
//!   x-tb-key:   hex(pubkey, 32 bytes)
//!   x-tb-ts:    unix millis
//!   x-tb-nonce: hex(16 random bytes)
//!   x-tb-sig:   hex(sig over "METHOD\nPATH\nhex(sha256(body))\nTS\nNONCE")

use axum::http::{HeaderMap, Method, StatusCode};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use sqlx::PgPool;

const MAX_SKEW_MS: i64 = 5 * 60 * 1000;

pub struct Caller {
    pub pubkey: [u8; 32],
}

fn header<'a>(h: &'a HeaderMap, name: &str) -> Result<&'a str, StatusCode> {
    h.get(name).and_then(|v| v.to_str().ok()).ok_or(StatusCode::UNAUTHORIZED)
}

pub async fn verify(
    db: &PgPool,
    method: &Method,
    path: &str,
    headers: &HeaderMap,
    body: &[u8],
) -> Result<Caller, StatusCode> {
    let key: [u8; 32] = hex::decode(header(headers, "x-tb-key")?)
        .ok()
        .and_then(|v| v.try_into().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;
    let ts: i64 = header(headers, "x-tb-ts")?.parse().map_err(|_| StatusCode::UNAUTHORIZED)?;
    let nonce_hex = header(headers, "x-tb-nonce")?;
    let sig: [u8; 64] = hex::decode(header(headers, "x-tb-sig")?)
        .ok()
        .and_then(|v| v.try_into().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let now = chrono::Utc::now().timestamp_millis();
    if (now - ts).abs() > MAX_SKEW_MS {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let msg = format!(
        "{}\n{}\n{}\n{}\n{}",
        method,
        path,
        hex::encode(Sha256::digest(body)),
        ts,
        nonce_hex
    );
    let vk = VerifyingKey::from_bytes(&key).map_err(|_| StatusCode::UNAUTHORIZED)?;
    vk.verify(msg.as_bytes(), &Signature::from_bytes(&sig))
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // Replay protection: a nonce may be used once.
    let nonce = hex::decode(nonce_hex).map_err(|_| StatusCode::UNAUTHORIZED)?;
    let inserted = sqlx::query("INSERT INTO seen_nonce (nonce) VALUES ($1) ON CONFLICT DO NOTHING")
        .bind(nonce)
        .execute(db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .rows_affected();
    if inserted == 0 {
        return Err(StatusCode::UNAUTHORIZED);
    }

    Ok(Caller { pubkey: key })
}
