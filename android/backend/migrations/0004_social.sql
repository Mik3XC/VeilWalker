-- Social layer: invites, mutual friendships, and a synced avatar index (one of four ASCII pictures).
-- Friends see only handle, clan, avatar and weekly step total. Nothing else is exposed.

ALTER TABLE account ADD COLUMN avatar SMALLINT NOT NULL DEFAULT 0 CHECK (avatar BETWEEN 0 AND 3);

-- One-time (or few-time) codes. kind 'friend' makes inviter and accepter friends; kind 'clan' also
-- lets the accepter join the inviter's clan.
CREATE TABLE invite (
    code       TEXT PRIMARY KEY,
    inviter    BYTEA NOT NULL REFERENCES account(pubkey) ON DELETE CASCADE,
    kind       TEXT NOT NULL CHECK (kind IN ('friend', 'clan')),
    clan_tag   TEXT REFERENCES clan(tag),
    uses_left  INT NOT NULL DEFAULT 1 CHECK (uses_left >= 0),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stored once per pair with a < b so a friendship can't be duplicated or half-exist.
CREATE TABLE friendship (
    a          BYTEA NOT NULL REFERENCES account(pubkey) ON DELETE CASCADE,
    b          BYTEA NOT NULL REFERENCES account(pubkey) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (a, b),
    CHECK (a < b)
);
CREATE INDEX friendship_b ON friendship (b);
