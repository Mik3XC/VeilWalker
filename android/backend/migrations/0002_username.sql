-- One permanent handle per account. Unique ignoring case, claimable once, never renamed or freed
-- (a deleted account's handle stays taken, so nobody can step into someone else's name).

ALTER TABLE account ADD COLUMN username TEXT;

CREATE UNIQUE INDEX account_username_lower ON account (lower(username));

CREATE FUNCTION username_is_permanent() RETURNS trigger AS $$
BEGIN
    IF OLD.username IS NOT NULL AND NEW.username IS DISTINCT FROM OLD.username THEN
        RAISE EXCEPTION 'username is permanent';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER username_no_rename BEFORE UPDATE OF username ON account
    FOR EACH ROW EXECUTE FUNCTION username_is_permanent();
