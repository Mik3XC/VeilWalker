//! Permanent handles: 5–20 chars of A–Z, a–z, 0–9 and _, unique ignoring case, claimed once.

const MIN: usize = 5;
const MAX: usize = 20;

/// Names nobody may claim: they'd read as official or as system output.
const RESERVED: &[&str] = &[
    "admin", "administrator", "veilwalker", "veil_walker", "trailbound", "support", "official",
    "moderator", "system", "root", "server", "staff", "security", "anonymous", "undefined",
];

#[derive(Debug, PartialEq)]
pub enum Invalid {
    Length,
    Characters,
    Reserved,
}

pub fn validate(name: &str) -> Result<(), Invalid> {
    if !(MIN..=MAX).contains(&name.len()) {
        return Err(Invalid::Length);
    }
    if !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_') {
        return Err(Invalid::Characters);
    }
    let lower = name.to_ascii_lowercase();
    if RESERVED.contains(&lower.as_str()) {
        return Err(Invalid::Reserved);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_good_handles() {
        assert_eq!(validate("ghost_77"), Ok(()));
        assert_eq!(validate("NullTrail"), Ok(()));
    }

    #[test]
    fn rejects_bad_handles() {
        assert_eq!(validate("abcd"), Err(Invalid::Length));
        assert_eq!(validate("a".repeat(21).as_str()), Err(Invalid::Length));
        assert_eq!(validate("bad name"), Err(Invalid::Characters));
        assert_eq!(validate("émile"), Err(Invalid::Characters));
        assert_eq!(validate("Admin"), Err(Invalid::Reserved));
    }
}
