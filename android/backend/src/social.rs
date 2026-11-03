//! Invites, friends and squad (clan) views. Everything is keyed by public key; friends see only
//! handle, clan tag, avatar index and steps over the last 7 days.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, Method, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{api_err, auth, ApiErr, AppState};

/// Unambiguous alphabet (no 0/O, 1/I/L) so codes survive being read aloud or typed.
const ALPHABET: &[u8] = b"23456789ABCDEFGHJKMNPQRSTUVWXYZ";

fn new_code() -> String {
    let bytes = uuid::Uuid::new_v4().into_bytes();
    let chars: String = bytes.iter().take(8).map(|b| ALPHABET[(*b as usize) % ALPHABET.len()] as char).collect();
    format!("VW-{}-{}", &chars[..4], &chars[4..])
}

fn ordered<'a>(x: &'a [u8], y: &'a [u8]) -> (&'a [u8], &'a [u8]) {
    if x < y { (x, y) } else { (y, x) }
}

const WEEK_STEPS_SQL: &str = "COALESCE((SELECT SUM(steps_passive + steps_sensor + steps_gps + steps_onion) FROM daily_summary d \
     WHERE d.pubkey = acc.pubkey AND d.day > CURRENT_DATE - 7), 0)::BIGINT";

fn server_err(_: sqlx::Error) -> ApiErr {
    api_err(StatusCode::INTERNAL_SERVER_ERROR, "server_error")
}

#[derive(Deserialize)]
pub struct ProfileReq {
    avatar: i16,
}

/// Syncs the chosen ASCII avatar (0-3) so friends and squadmates see it.
pub async fn set_profile(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<StatusCode, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/profile", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: ProfileReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    if !(0..=3).contains(&req.avatar) {
        return Err(api_err(StatusCode::BAD_REQUEST, "invalid_avatar"));
    }
    sqlx::query("UPDATE account SET avatar = $2 WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .bind(req.avatar)
        .execute(&s.db)
        .await
        .map_err(server_err)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct InviteReq {
    kind: String,
}

#[derive(Serialize)]
pub struct InviteResp {
    code: String,
    kind: String,
    clan: Option<String>,
    expires_in_days: i32,
}

/// Creates a 7-day invite. Friend invites work once; clan invites work for up to 10 people.
/// Errors: bad_kind, no_handle (claim a handle first), no_clan (for clan invites).
pub async fn create_invite(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<InviteResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/invites", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: InviteReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let row = sqlx::query("SELECT username, clan_tag FROM account WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&s.db)
        .await
        .map_err(server_err)?
        .ok_or_else(|| api_err(StatusCode::FORBIDDEN, "no_account"))?;
    if row.get::<Option<String>, _>("username").is_none() {
        return Err(api_err(StatusCode::CONFLICT, "no_handle"));
    }
    let clan: Option<String> = row.get("clan_tag");
    let (uses, clan_tag) = match req.kind.as_str() {
        "friend" => (1, None),
        "clan" => (10, Some(clan.clone().ok_or_else(|| api_err(StatusCode::CONFLICT, "no_clan"))?)),
        _ => return Err(api_err(StatusCode::BAD_REQUEST, "bad_kind")),
    };
    let code = new_code();
    sqlx::query("INSERT INTO invite (code, inviter, kind, clan_tag, uses_left, expires_at) VALUES ($1,$2,$3,$4,$5, now() + interval '7 days')")
        .bind(&code)
        .bind(caller.pubkey.as_slice())
        .bind(&req.kind)
        .bind(&clan_tag)
        .bind(uses)
        .execute(&s.db)
        .await
        .map_err(server_err)?;
    Ok(Json(InviteResp { code, kind: req.kind, clan: clan_tag, expires_in_days: 7 }))
}

#[derive(Deserialize)]
pub struct AcceptReq {
    code: String,
}

#[derive(Serialize)]
pub struct AcceptResp {
    friend: Option<String>,
    joined_clan: Option<String>,
}

/// Accepts an invite: always makes inviter and accepter friends; a clan invite also joins the clan
/// if the accepter isn't in one. Errors: not_found, expired, own_invite.
pub async fn accept_invite(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<AcceptResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/invites/accept", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: AcceptReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let code = req.code.trim().to_ascii_uppercase();
    let mut tx = s.db.begin().await.map_err(server_err)?;
    let inv = sqlx::query("SELECT inviter, kind, clan_tag, uses_left, expires_at < now() AS expired FROM invite WHERE code = $1 FOR UPDATE")
        .bind(&code)
        .fetch_optional(&mut *tx)
        .await
        .map_err(server_err)?
        .ok_or_else(|| api_err(StatusCode::NOT_FOUND, "not_found"))?;
    let inviter: Vec<u8> = inv.get("inviter");
    if inviter.as_slice() == caller.pubkey.as_slice() {
        return Err(api_err(StatusCode::CONFLICT, "own_invite"));
    }
    if inv.get::<bool, _>("expired") || inv.get::<i32, _>("uses_left") <= 0 {
        return Err(api_err(StatusCode::GONE, "expired"));
    }
    let (a, b) = ordered(&inviter, &caller.pubkey);
    sqlx::query("INSERT INTO friendship (a, b) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(a)
        .bind(b)
        .execute(&mut *tx)
        .await
        .map_err(server_err)?;
    let mut joined = None;
    if inv.get::<String, _>("kind") == "clan" {
        let tag: Option<String> = inv.get("clan_tag");
        if let Some(tag) = tag {
            let members: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM account WHERE clan_tag = $1")
                .bind(&tag)
                .fetch_one(&mut *tx)
                .await
                .map_err(server_err)?;
            if members < crate::CLAN_MAX {
                let r = sqlx::query("UPDATE account SET clan_tag = $2 WHERE pubkey = $1 AND clan_tag IS NULL")
                    .bind(caller.pubkey.as_slice())
                    .bind(&tag)
                    .execute(&mut *tx)
                    .await
                    .map_err(server_err)?;
                if r.rows_affected() == 1 {
                    joined = Some(tag);
                }
            }
        }
    }
    sqlx::query("UPDATE invite SET uses_left = uses_left - 1 WHERE code = $1")
        .bind(&code)
        .execute(&mut *tx)
        .await
        .map_err(server_err)?;
    let friend: Option<String> = sqlx::query_scalar("SELECT username FROM account WHERE pubkey = $1")
        .bind(&inviter)
        .fetch_one(&mut *tx)
        .await
        .map_err(server_err)?;
    tx.commit().await.map_err(server_err)?;
    Ok(Json(AcceptResp { friend, joined_clan: joined }))
}

#[derive(Serialize)]
pub struct Person {
    id: String,
    handle: Option<String>,
    clan: Option<String>,
    avatar: i16,
    week_steps: i64,
}

fn person(r: &sqlx::postgres::PgRow) -> Person {
    Person {
        id: hex::encode(r.get::<Vec<u8>, _>("pubkey")),
        handle: r.get("username"),
        clan: r.get("clan_tag"),
        avatar: r.get("avatar"),
        week_steps: r.get("week_steps"),
    }
}

/// The caller's friends, most steps this week first.
pub async fn friends(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<Vec<Person>>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/friends", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let rows = sqlx::query(&format!(
        "SELECT acc.pubkey, acc.username, acc.clan_tag, acc.avatar, {WEEK_STEPS_SQL} AS week_steps
         FROM friendship f JOIN account acc ON acc.pubkey = CASE WHEN f.a = $1 THEN f.b ELSE f.a END
         WHERE f.a = $1 OR f.b = $1
         ORDER BY week_steps DESC LIMIT 200"
    ))
    .bind(caller.pubkey.as_slice())
    .fetch_all(&s.db)
    .await
    .map_err(server_err)?;
    Ok(Json(rows.iter().map(person).collect()))
}

#[derive(Deserialize)]
pub struct RemoveReq {
    id: String,
}

/// Ends a friendship (for both sides).
pub async fn remove_friend(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<StatusCode, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/friends/remove", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let req: RemoveReq = serde_json::from_slice(&body).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_request"))?;
    let other = hex::decode(&req.id).map_err(|_| api_err(StatusCode::BAD_REQUEST, "bad_id"))?;
    let (a, b) = ordered(&caller.pubkey, &other);
    sqlx::query("DELETE FROM friendship WHERE a = $1 AND b = $2")
        .bind(a)
        .bind(b)
        .execute(&s.db)
        .await
        .map_err(server_err)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Serialize)]
pub struct SquadResp {
    clan: Option<String>,
    members: Vec<Person>,
    week_total: i64,
}

/// The caller's clan as a squad: members ranked by steps this week.
pub async fn squad(State(s): State<AppState>, method: Method, headers: HeaderMap, body: Bytes) -> Result<Json<SquadResp>, ApiErr> {
    let caller = auth::verify(&s.db, &method, "/v1/squad", &headers, &body).await.map_err(|c| api_err(c, "unauthorized"))?;
    let clan: Option<String> = sqlx::query_scalar("SELECT clan_tag FROM account WHERE pubkey = $1")
        .bind(caller.pubkey.as_slice())
        .fetch_optional(&s.db)
        .await
        .map_err(server_err)?
        .flatten();
    let Some(tag) = clan.clone() else {
        return Ok(Json(SquadResp { clan: None, members: vec![], week_total: 0 }));
    };
    let rows = sqlx::query(&format!(
        "SELECT acc.pubkey, acc.username, acc.clan_tag, acc.avatar, {WEEK_STEPS_SQL} AS week_steps
         FROM account acc WHERE acc.clan_tag = $1 ORDER BY week_steps DESC LIMIT 50"
    ))
    .bind(&tag)
    .fetch_all(&s.db)
    .await
    .map_err(server_err)?;
    let members: Vec<Person> = rows.iter().map(person).collect();
    let week_total = members.iter().map(|m| m.week_steps).sum();
    Ok(Json(SquadResp { clan, members, week_total }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invite_codes_are_readable() {
        let c = new_code();
        assert_eq!(c.len(), 12);
        assert!(c.starts_with("VW-"));
        assert!(c[3..].chars().filter(|ch| *ch != '-').all(|ch| ALPHABET.contains(&(ch as u8))));
    }

    #[test]
    fn pair_order_is_canonical() {
        assert_eq!(ordered(&[2], &[1]), (&[1u8][..], &[2u8][..]));
        assert_eq!(ordered(&[1], &[2]), (&[1u8][..], &[2u8][..]));
    }
}
