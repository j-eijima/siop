// The record of the request this browser sent, and the rule that one response
// — and only one — is accepted for it. Kept apart from the page so the rule
// can be tested under Node.

/// The lock every tab of this origin takes to claim the request.
const LOCK = "siop-rp.pending-request";

/// Nonces already accepted, each kept until the token it was accepted with has
/// expired. Before then nothing but this list stops that token being replayed;
/// after it, the token fails its exp check anyway, so the nonce can go. A count
/// would not do: the verifier puts no ceiling on a token's lifetime.
const SPENT_KEY = "siop-rp.spent-nonces";

/// The verifier's allowance for clock skew, which a replay can use too.
const SKEW_SECONDS = 120;

/// The nonces whose tokens could still pass, or null if the list cannot be
/// read — in which case nothing can be shown to be unspent.
function spentNonces(storage, now) {
  let entries;
  try {
    entries = JSON.parse(storage.getItem(SPENT_KEY) ?? "[]");
  } catch {
    return null;
  }
  if (!Array.isArray(entries)) return null;
  return entries.filter((entry) => typeof entry?.until === "number" && entry.until > now);
}

/// `storage` is localStorage, or anything with its getItem, setItem and
/// removeItem. `locks` is navigator.locks, or anything with its
/// request(name, callback).
export function pendingRequest(storage, key, locks) {
  const record = storage.getItem(key);
  const value = JSON.parse(record ?? "null");
  let accepted = false;

  return {
    /// What was sent, or null when this browser has no record of it.
    value,

    /// Claims the request for a response that has passed every check against
    /// it, whose token expires at `expiresAt` (seconds since the epoch).
    ///
    /// True for the page that claims it first, and again whenever that page
    /// asks. False for any other page: the record is gone because another tab
    /// accepted a response to it, it has been replaced by a newer request, or
    /// its nonce was accepted before with a token that is still valid. One
    /// response authenticates; a second, however valid, is a replay.
    ///
    /// Finding the record and removing it happen under a lock every tab of
    /// this origin shares. localStorage has no compare-and-remove of its own,
    /// so without the lock two tabs could both find the record and both
    /// remove it. A browser that offers no locks cannot make that promise, and
    /// accepts nothing; nor is anything accepted without an expiry to keep its
    /// nonce until.
    async accept({ expiresAt, now = Date.now() / 1000 } = {}) {
      if (accepted) return true;
      if (record === null || !locks || typeof expiresAt !== "number") return false;
      accepted = await locks.request(LOCK, () => {
        if (storage.getItem(key) !== record) return false;
        // A record can come back after it was used — written again by a
        // request page left open, say. The nonce is what makes a request
        // one-shot, so a nonce accepted once is not accepted again while its
        // token could still pass.
        const spent = spentNonces(storage, now);
        if (spent === null || spent.some((entry) => entry.nonce === value.nonce)) return false;
        storage.removeItem(key);
        storage.setItem(SPENT_KEY, JSON.stringify([
          ...spent,
          { nonce: value.nonce, until: expiresAt + SKEW_SECONDS },
        ]));
        return true;
      });
      return accepted;
    },
  };
}
