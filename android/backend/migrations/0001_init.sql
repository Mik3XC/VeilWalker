-- Trailbound schema. Accounts are public keys: no email, phone or name. No IP column anywhere, by design.

CREATE TABLE account (
    pubkey      BYTEA PRIMARY KEY CHECK (length(pubkey) = 32),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid        BOOLEAN NOT NULL DEFAULT false,
    emblem_tier SMALLINT NOT NULL DEFAULT 0
);

-- Replay protection for signed requests (5-minute window; pruned by the app).
CREATE TABLE seen_nonce (
    nonce   BYTEA PRIMARY KEY,
    seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE daily_summary (
    pubkey          BYTEA NOT NULL REFERENCES account(pubkey) ON DELETE CASCADE,
    day             DATE NOT NULL,
    steps_passive   BIGINT NOT NULL,
    steps_sensor    BIGINT NOT NULL,
    steps_gps       BIGINT NOT NULL,
    steps_onion     BIGINT NOT NULL,   -- only credited if the request actually arrived via the onion service
    verdict         REAL NOT NULL,
    held_for_review BOOLEAN NOT NULL DEFAULT false,
    client_sig      BYTEA NOT NULL,
    PRIMARY KEY (pubkey, day)
);

-- Append-only, per-account hash chain. Same hashing as LedgerRepository.hash() on Android.
CREATE TABLE ledger_entry (
    pubkey      BYTEA NOT NULL REFERENCES account(pubkey),
    seq         BIGINT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('earn', 'redeem', 'adjust')),
    amount      BIGINT NOT NULL,        -- milli-points
    reason_code TEXT NOT NULL,
    ref_id      TEXT NOT NULL,
    ts_ms       BIGINT NOT NULL,
    prev_hash   BYTEA NOT NULL,
    entry_hash  BYTEA NOT NULL,
    server_sig  BYTEA NOT NULL,
    PRIMARY KEY (pubkey, seq)
);

CREATE FUNCTION ledger_append_only() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'ledger_entry is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_no_update BEFORE UPDATE OR DELETE ON ledger_entry
    FOR EACH ROW EXECUTE FUNCTION ledger_append_only();

-- Daily Merkle root over all new entries: today an audit trail, later the on-chain anchor.
CREATE TABLE merkle_root (
    day  DATE PRIMARY KEY,
    root BYTEA NOT NULL,
    leaf_count BIGINT NOT NULL
);

-- E2E-encrypted backup for BIP39 restore / device transfer. The server can't read it.
CREATE TABLE backup_blob (
    pubkey     BYTEA PRIMARY KEY REFERENCES account(pubkey) ON DELETE CASCADE,
    ciphertext BYTEA NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
