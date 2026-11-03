//! Server-authoritative points ledger. The server mints; clients only propose via signed summaries.

use ed25519_dalek::{Signer, SigningKey};
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Postgres, Row, Transaction};

pub const GENESIS: [u8; 32] = [0u8; 32];

/// Must match `LedgerRepository.hash()` on Android byte for byte.
pub fn entry_hash(prev: &[u8], seq: i64, kind: &str, amount: i64, reason: &str, ref_id: &str, ts_ms: i64) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(prev);
    h.update(seq.to_be_bytes());
    h.update(kind.as_bytes());
    h.update(amount.to_be_bytes());
    h.update(reason.as_bytes());
    h.update(ref_id.as_bytes());
    h.update(ts_ms.to_be_bytes());
    h.finalize().into()
}

/// Steps-to-points policy. Mirrors core/ledger PointsPolicy.kt; the server's copy is the one that counts.
/// No daily cap: every verified step counts (abuse is caught by the verdict and the 60k/day hold).
pub fn milli_points(passive: i64, sensor: i64, gps: i64, onion: i64, verdict: f32) -> i64 {
    [(onion, 1250), (gps, 1000), (sensor, 850), (passive, 500)]
        .iter()
        .map(|&(steps, permille)| (steps.max(0) as f64 * permille as f64 * verdict as f64 / 1000.0) as i64)
        .sum()
}

pub struct Minted {
    pub seq: i64,
    pub amount: i64,
}

/// Mints the difference between what a day's steps are worth now and what was already minted for that day.
/// Lets a phone sync the same day many times (points appear during the day) without double-minting.
pub async fn mint_daily(db: &PgPool, signer: &SigningKey, pubkey: &[u8], day: &str, worth_milli: i64) -> anyhow::Result<Option<Minted>> {
    let mut tx = db.begin().await?;
    lock_account(&mut tx, pubkey).await?;
    let already: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::BIGINT FROM ledger_entry WHERE pubkey = $1 AND reason_code = 'daily_steps' AND ref_id = $2",
    )
    .bind(pubkey)
    .bind(day)
    .fetch_one(&mut *tx)
    .await?;
    let delta = worth_milli - already;
    let minted = if delta > 0 {
        Some(append_locked(&mut tx, signer, pubkey, "earn", delta, "daily_steps", day).await?)
    } else {
        None
    };
    tx.commit().await?;
    Ok(minted)
}

/// Locks the account row so concurrent appends can't fork its chain.
async fn lock_account(tx: &mut Transaction<'_, Postgres>, pubkey: &[u8]) -> anyhow::Result<()> {
    sqlx::query("SELECT pubkey FROM account WHERE pubkey = $1 FOR UPDATE")
        .bind(pubkey)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn append_locked(
    tx: &mut Transaction<'_, Postgres>,
    signer: &SigningKey,
    pubkey: &[u8],
    kind: &str,
    amount: i64,
    reason: &str,
    ref_id: &str,
) -> anyhow::Result<Minted> {
    let head = sqlx::query("SELECT seq, entry_hash FROM ledger_entry WHERE pubkey = $1 ORDER BY seq DESC LIMIT 1")
        .bind(pubkey)
        .fetch_optional(&mut **tx)
        .await?;
    let (seq, prev): (i64, Vec<u8>) = match head {
        Some(r) => (r.get::<i64, _>("seq") + 1, r.get("entry_hash")),
        None => (1, GENESIS.to_vec()),
    };

    let ts_ms = chrono::Utc::now().timestamp_millis();
    let hash = entry_hash(&prev, seq, kind, amount, reason, ref_id, ts_ms);
    let sig = signer.sign(&hash);

    sqlx::query(
        "INSERT INTO ledger_entry (pubkey, seq, kind, amount, reason_code, ref_id, ts_ms, prev_hash, entry_hash, server_sig)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
    )
    .bind(pubkey)
    .bind(seq)
    .bind(kind)
    .bind(amount)
    .bind(reason)
    .bind(ref_id)
    .bind(ts_ms)
    .bind(&prev)
    .bind(hash.as_slice())
    .bind(sig.to_bytes().as_slice())
    .execute(&mut **tx)
    .await?;

    Ok(Minted { seq, amount })
}

/// One ledger row as the phone receives it (bytes hex-encoded).
#[derive(serde::Serialize)]
pub struct EntryDto {
    pub seq: i64,
    pub kind: String,
    pub amount: i64,
    pub reason_code: String,
    pub ref_id: String,
    pub ts_ms: i64,
    pub prev_hash: String,
    pub entry_hash: String,
    pub server_sig: String,
}

pub async fn entries_after(db: &PgPool, pubkey: &[u8], after: i64) -> anyhow::Result<Vec<EntryDto>> {
    let rows = sqlx::query(
        "SELECT seq, kind, amount, reason_code, ref_id, ts_ms, prev_hash, entry_hash, server_sig
         FROM ledger_entry WHERE pubkey = $1 AND seq > $2 ORDER BY seq LIMIT 500",
    )
    .bind(pubkey)
    .bind(after)
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| EntryDto {
            seq: r.get("seq"),
            kind: r.get("kind"),
            amount: r.get("amount"),
            reason_code: r.get("reason_code"),
            ref_id: r.get("ref_id"),
            ts_ms: r.get("ts_ms"),
            prev_hash: hex::encode(r.get::<Vec<u8>, _>("prev_hash")),
            entry_hash: hex::encode(r.get::<Vec<u8>, _>("entry_hash")),
            server_sig: hex::encode(r.get::<Vec<u8>, _>("server_sig")),
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_step_counts() {
        // Same case as PointsPolicyTest.kt
        assert_eq!(milli_points(10_000, 0, 0, 5_000, 1.0), 11_250);
    }

    #[test]
    fn no_daily_cap() {
        assert_eq!(milli_points(0, 0, 30_000, 0, 1.0), 30_000);
    }
}
