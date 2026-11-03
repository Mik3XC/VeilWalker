-- Clans: a short tag shown before the handle, e.g. [ROX] HashCat. One clan per account.
-- Tags are unique ignoring case and permanent (a clan keeps its tag even if everyone leaves).

CREATE TABLE clan (
    tag        TEXT PRIMARY KEY CHECK (tag ~ '^[A-Z0-9]{2,4}$'),
    owner      BYTEA NOT NULL REFERENCES account(pubkey),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE account ADD COLUMN clan_tag TEXT REFERENCES clan(tag);
CREATE INDEX account_clan ON account (clan_tag);
