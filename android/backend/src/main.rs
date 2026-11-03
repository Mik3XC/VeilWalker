//! VeilWalker API (Railway). Privacy rules enforced here:
//!  - no IP is ever read or logged (no ConnectInfo, no request logging middleware)
//!  - identity is a public key; requests are Ed25519-signed (see auth.rs)
//!  - only signed daily summaries arrive, never raw sensor or GPS data

mod auth;
mod ledger;
mod social;
mod username;

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::{Query, State};
use axum::http::{HeaderMap, Method, StatusCode};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use ed25519_dalek::SigningKey;
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};

#[derive(Clone)]
pub(crate) struct AppState {
    db: PgPool,
    signer: Arc<SigningKey>,
    /// True on the loopback listener that only the tor daemon's HiddenServicePort points at.
    via_onion: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Log level only. There's deliberately no request/IP logging layer.
    tracing_subscriber::fmt().with_env_filter("info").init();

    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&std::env::var("DATABASE_URL")?)
        .await?;
    sqlx::migrate!("./migrations").run(&db).await?;

    let seed: [u8; 32] = hex::decode(std::env::var("SERVER_SIGNING_KEY_HEX")?)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("SERVER_SIGNING_KEY_HEX must be 32 bytes"))?;
    let state = AppState { db, signer: Arc::new(SigningKey::from_bytes(&seed)), via_onion: false };
    let onion_state = AppState { via_onion: true, ..state.clone() };

    let router = || Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/v1/register", post(register))
        .route("/v1/sync", post(sync))
        .route("/v1/ledger", get(get_ledger))
        .route("/v1/me", get(me))
        .route("/v1/username", post(claim_username))
        .route("/v1/clan", post(clan_create))
        .route("/v1/clan/join", post(clan_join))
        .route("/v1/clan/leave", post(clan_leave))
        .route("/v1/profile", post(social::set_profile))
        .route("/v1/invites", post(social::create_invite))
        .route("/v1/invites/accept", post(social::accept_invite))
        .route("/v1/friends", get(social::friends))
        .route("/v1/friends/remove", post(social::remove_friend))
        .route("/v1/squad", get(social::squad))
        .route("/v1/history", get(history))
        .route("/v1/backup", put(put_backup).get(get_backup))
        .route("/v1/account", axum::routing::delete(delete_account));

    // Onion listener: loopback only, so nothing but the in-container tor daemon can reach it.
    // Being on this listener is the proof a request came over Tor; no header can fake it.
    let onion_listener = tokio::net::TcpListener::bind("127.0.0.1:8081").await?;
    let onion_app = router().with_state(onion_state);
    tokio::spawn(async move { axum::serve(onion_listener, onion_app).await });

    // Clearnet listener for Railway's public proxy.
    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await?;
    axum::serve(listener, router().with_state(state)).await?;
    Ok(())
}

async fn register(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<StatusCode, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/register", &headers, &body).await?;
    sqlx::query("INSERT INTO account (pubkey) VALUES ($1) ON CONFLICT DO NOTHING")
        .bind(caller.pubkey.as_slice())
        .execute(&s.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct SyncReq {
    day: chrono::NaiveDate,
    steps_passive: i64,
    steps_sensor: i64,
    steps_gps: i64,
    steps_onion: i64,
    verdict: f32,
    summary_sig: String, // hex; device signature over the canonical summary
}

#[derive(Serialize)]
struct SyncResp {
    /// Milli-points minted by this sync (0 if nothing new or held).
    minted_milli: i64,
    held_for_review: bool,
    seq: Option<i64>,
}

/// Upserts a day's running totals and mints only the newly earned difference. A phone can sync the same day
/// repeatedly; totals may only grow, so replaying an old summary or lowering a count can't mint anything.
async fn sync(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<SyncResp>, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/sync", &headers, &body).await?;
    let req: SyncReq = serde_json::from_slice(&body).map_err(|_| StatusCode::BAD_REQUEST)?;

    let today = chrono::Utc::now().date_naive();
    if req.day > today + chrono::Days::new(1) || req.day < today - chrono::Days::new(7) {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }
    if [req.steps_passive, req.steps_sensor, req.steps_gps, req.steps_onion].iter().any(|v| *v < 0) {
        return Err(StatusCode::BAD_REQUEST);
    }

    // Onion steps only earn the onion rate if this request really came over Tor; otherwise they count as GPS-verified.
    // The split is sticky: onion steps already proven over Tor stay onion when a later sync arrives over clearnet.
    let prior = sqlx::query("SELECT steps_passive, steps_sensor, steps_gps, steps_onion, held_for_review FROM daily_summary WHERE pubkey = $1 AND day = $2")
        .bind(caller.pubkey.as_slice())
        .bind(req.day)
        .fetch_optional(&s.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let prior_onion: i64 = prior.as_ref().map(|r| r.get("steps_onion")).unwrap_or(0);
    let onion = if s.via_onion { req.steps_onion } else { prior_onion.min(req.steps_onion) };
    let gps = req.steps_gps + (req.steps_onion - onion);

    if let Some(p) = &prior {
        let grew = req.steps_passive >= p.get::<i64, _>("steps_passive")
            && req.steps_sensor >= p.get::<i64, _>("steps_sensor")
            && gps + onion >= p.get::<i64, _>("steps_gps") + p.get::<i64, _>("steps_onion");
        if !grew {
            return Err(StatusCode::CONFLICT);
        }
    }

    let total = req.steps_passive + req.steps_sensor + gps + onion;
    let held = prior.as_ref().map(|r| r.get::<bool, _>("held_for_review")).unwrap_or(false)
        || total > 60_000
        || !(0.0..=1.0).contains(&req.verdict);

    // Only registered accounts can sync.
    sqlx::query_scalar::<_, i32>("SELECT 1 FROM account WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&s.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::FORBIDDEN)?;

    sqlx::query(
        "INSERT INTO daily_summary (pubkey, day, steps_passive, steps_sensor, steps_gps, steps_onion, verdict, held_for_review, client_sig)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (pubkey, day) DO UPDATE SET
           steps_passive = EXCLUDED.steps_passive, steps_sensor = EXCLUDED.steps_sensor,
           steps_gps = EXCLUDED.steps_gps, steps_onion = EXCLUDED.steps_onion,
           verdict = EXCLUDED.verdict, held_for_review = EXCLUDED.held_for_review, client_sig = EXCLUDED.client_sig",
    )
    .bind(caller.pubkey.as_slice())
    .bind(req.day)
    .bind(req.steps_passive)
    .bind(req.steps_sensor)
    .bind(gps)
    .bind(onion)
    .bind(req.verdict)
    .bind(held)
    .bind(hex::decode(&req.summary_sig).map_err(|_| StatusCode::BAD_REQUEST)?)
    .execute(&s.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if held {
        return Ok(Json(SyncResp { minted_milli: 0, held_for_review: true, seq: None }));
    }

    let worth = ledger::milli_points(req.steps_passive, req.steps_sensor, gps, onion, req.verdict);
    let minted = ledger::mint_daily(&s.db, &s.signer, &caller.pubkey, &req.day.to_string(), worth)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(match minted {
        Some(m) => SyncResp { minted_milli: m.amount, held_for_review: false, seq: Some(m.seq) },
        None => SyncResp { minted_milli: 0, held_for_review: false, seq: None },
    }))
}

#[derive(Deserialize)]
struct LedgerQuery {
    #[serde(default)]
    after: i64,
}

/// The caller's own signed ledger entries after `after`. Phones keep the full chain locally, so the server
/// can rebuild balances from them if its database is ever lost.
async fn get_ledger(
    State(s): State<AppState>,
    method: Method,
    headers: HeaderMap,
    Query(q): Query<LedgerQuery>,
    body: Bytes,
) -> Result<Json<Vec<ledger::EntryDto>>, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/ledger", &headers, &body).await?;
    ledger::entries_after(&s.db, &caller.pubkey, q.after)
        .await
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

#[derive(Serialize)]
struct MeResp {
    username: Option<String>,
    clan: Option<String>,
    avatar: i16,
}

/// Lets a restored phone recover its handle.
async fn me(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<MeResp>, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/me", &headers, &body).await?;
    let row = sqlx::query("SELECT username, clan_tag, avatar FROM account WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&s.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::FORBIDDEN)?;
    Ok(Json(MeResp { username: row.get("username"), clan: row.get("clan_tag"), avatar: row.get("avatar") }))
}

#[derive(Deserialize)]
struct ClaimReq {
    username: String,
}

/// Claims the caller's permanent handle. Errors come back as {"error": "..."} so the app can explain them:
/// invalid_length / invalid_characters / reserved (400), taken / already_claimed (409).
async fn claim_username(
    State(s): State<AppState>,
    method: Method,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<MeResp>, (StatusCode, Json<serde_json::Value>)> {
    let err = |code: StatusCode, e: &str| (code, Json(serde_json::json!({ "error": e })));
    let caller = auth::verify(&s.db, &method, "/v1/username", &headers, &body)
        .await
        .map_err(|c| err(c, "unauthorized"))?;
    let req: ClaimReq = serde_json::from_slice(&body).map_err(|_| err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let name = req.username.trim().to_string();
    username::validate(&name).map_err(|e| {
        err(
            StatusCode::BAD_REQUEST,
            match e {
                username::Invalid::Length => "invalid_length",
                username::Invalid::Characters => "invalid_characters",
                username::Invalid::Reserved => "reserved",
            },
        )
    })?;

    let res = sqlx::query("UPDATE account SET username = $2 WHERE pubkey = $1 AND username IS NULL")
        .bind(caller.pubkey.as_slice())
        .bind(&name)
        .execute(&s.db)
        .await;
    match res {
        Ok(r) if r.rows_affected() == 1 => Ok(Json(MeResp { username: Some(name), clan: None, avatar: 0 })),
        Ok(_) => Err(err(StatusCode::CONFLICT, "already_claimed")),
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => Err(err(StatusCode::CONFLICT, "taken")),
        Err(_) => Err(err(StatusCode::INTERNAL_SERVER_ERROR, "server_error")),
    }
}

#[derive(Deserialize)]
struct ClanReq {
    tag: String,
}

#[derive(Serialize)]
struct ClanResp {
    clan: Option<String>,
}

pub(crate) type ApiErr = (StatusCode, Json<serde_json::Value>);

pub(crate) fn api_err(code: StatusCode, e: &str) -> ApiErr {
    (code, Json(serde_json::json!({ "error": e })))
}

/// 2-4 chars, A-Z and 0-9, stored upper-case so [rox] and [ROX] are the same clan.
fn clan_tag(raw: &str) -> Result<String, ApiErr> {
    let tag = raw.trim().to_ascii_uppercase();
    if (2..=4).contains(&tag.len()) && tag.bytes().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit()) {
        Ok(tag)
    } else {
        Err(api_err(StatusCode::BAD_REQUEST, "invalid_tag"))
    }
}

/// Max members per clan: small enough that a clan stays a crew.
pub(crate) const CLAN_MAX: i64 = 50;

/// Creates a clan with the caller as owner and first member. Errors: invalid_tag, taken, in_clan.
async fn clan_create(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<ClanResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/clan", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: ClanReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let tag = clan_tag(&req.tag)?;
    let mut tx = s.db.begin().await.map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    let current: Option<String> = sqlx::query_scalar("SELECT clan_tag FROM account WHERE pubkey = $1 FOR UPDATE")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?
        .ok_or_else(|| api_err(StatusCode::FORBIDDEN, "no_account"))?;
    if current.is_some() {
        return Err(api_err(StatusCode::CONFLICT, "in_clan"));
    }
    match sqlx::query("INSERT INTO clan (tag, owner) VALUES ($1, $2)").bind(&tag).bind(caller.pubkey.as_slice()).execute(&mut *tx).await {
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => return Err(api_err(StatusCode::CONFLICT, "taken")),
        Err(_) => return Err(api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error")),
        Ok(_) => {}
    }
    sqlx::query("UPDATE account SET clan_tag = $2 WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .bind(&tag)
        .execute(&mut *tx)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    tx.commit().await.map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    Ok(Json(ClanResp { clan: Some(tag) }))
}

/// Joins an existing clan. Errors: invalid_tag, not_found, full, in_clan.
async fn clan_join(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<ClanResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/clan/join", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: ClanReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let tag = clan_tag(&req.tag)?;
    let mut tx = s.db.begin().await.map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    // Lock the clan row so two joins can't both squeeze in past the cap.
    let exists: Option<String> = sqlx::query_scalar("SELECT tag FROM clan WHERE tag = $1 FOR UPDATE")
        .bind(&tag)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    if exists.is_none() {
        return Err(api_err(StatusCode::NOT_FOUND, "not_found"));
    }
    let members: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM account WHERE clan_tag = $1")
        .bind(&tag)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    if members >= CLAN_MAX {
        return Err(api_err(StatusCode::CONFLICT, "full"));
    }
    let r = sqlx::query("UPDATE account SET clan_tag = $2 WHERE pubkey = $1 AND clan_tag IS NULL")
        .bind(caller.pubkey.as_slice())
        .bind(&tag)
        .execute(&mut *tx)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    if r.rows_affected() == 0 {
        return Err(api_err(StatusCode::CONFLICT, "in_clan"));
    }
    tx.commit().await.map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    Ok(Json(ClanResp { clan: Some(tag) }))
}

/// Leaves the current clan (the clan and its tag remain).
async fn clan_leave(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<ClanResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/clan/leave", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    sqlx::query("UPDATE account SET clan_tag = NULL WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .execute(&s.db)
        .await
        .map_err(|_| api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error"))?;
    Ok(Json(ClanResp { clan: None }))
}

#[derive(Serialize)]
struct DayDto {
    day: chrono::NaiveDate,
    steps_passive: i64,
    steps_sensor: i64,
    steps_gps: i64,
    steps_onion: i64,
}

/// The caller's own synced daily totals, oldest first. A restored phone re-imports these so lifetime
/// steps, route progress and badges come back (raw sensor history never left the old phone).
async fn history(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<Vec<DayDto>>, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/history", &headers, &body).await?;
    let rows = sqlx::query(
        "SELECT day, steps_passive, steps_sensor, steps_gps, steps_onion FROM daily_summary WHERE pubkey = $1 ORDER BY day LIMIT 3660",
    )
    .bind(caller.pubkey.as_slice())
    .fetch_all(&s.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(
        rows.iter()
            .map(|r| DayDto {
                day: r.get("day"),
                steps_passive: r.get("steps_passive"),
                steps_sensor: r.get("steps_sensor"),
                steps_gps: r.get("steps_gps"),
                steps_onion: r.get("steps_onion"),
            })
            .collect(),
    ))
}

async fn put_backup(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<StatusCode, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/backup", &headers, &body).await?;
    if body.len() > 20 * 1024 * 1024 {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }
    sqlx::query(
        "INSERT INTO backup_blob (pubkey, ciphertext) VALUES ($1, $2)
         ON CONFLICT (pubkey) DO UPDATE SET ciphertext = EXCLUDED.ciphertext, updated_at = now()",
    )
    .bind(caller.pubkey.as_slice())
    .bind(body.as_ref())
    .execute(&s.db)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn get_backup(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Vec<u8>, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/backup", &headers, &body).await?;
    sqlx::query_scalar::<_, Vec<u8>>("SELECT ciphertext FROM backup_blob WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&s.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
}

/// Play requires account deletion. Ledger rows are kept (append-only, needed for audit) but are only linked to a
/// public key, which is meaningless once the user's seed is gone. Summaries and backup are deleted.
async fn delete_account(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<StatusCode, StatusCode> {
    let caller = auth::verify(&s.db, &method, "/v1/account", &headers, &body).await?;
    for q in ["DELETE FROM daily_summary WHERE pubkey = $1", "DELETE FROM backup_blob WHERE pubkey = $1"] {
        sqlx::query(q)
            .bind(caller.pubkey.as_slice())
            .execute(&s.db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    Ok(StatusCode::NO_CONTENT)
}
