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
  if (entries.some((entry) => typeof entry?.nonce !== "string" ||
      !Number.isFinite(entry.until))) return null;
  return entries.filter((entry) => entry.until > now);
}

/// `storage` is localStorage, or anything with its getItem, setItem and
/// removeItem. `locks` is navigator.locks, or anything with its
/// request(name, callback).
export function pendingRequest(storage, key, locks) {
  let record = null;
  let value = null;
  let failure = null;
  try {
    record = storage.getItem(key);
    value = JSON.parse(record ?? "null");
    if (value !== null && (typeof value.nonce !== "string" || !value.nonce ||
        typeof value.audience !== "string" || !value.audience ||
        (value.state !== undefined && typeof value.state !== "string"))) throw new Error();
    if (value?.requestURL !== undefined) {
      if (typeof value.requestURL !== "string") throw new Error();
      new URL(value.requestURL);
    }
    if (value) Object.freeze(value);
  } catch {
    value = null;
    failure = "unavailable";
  }
  let accepted = false;
  let claim = null;

  return {
    /// What was sent, or null when this browser has no record of it.
    value,
    get accepted() { return accepted; },
    get failure() { return failure; },

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
    ///
    /// Calls that overlap on one page — a redraw while the first still waits
    /// for the lock — share the first one's claim, and once true the answer
    /// stays true: a page claims once, and never loses a claim to its own
    /// redraw. `isCurrent` is asked again once the lock is taken, since what
    /// the page expects can change while it waits; false then claims nothing.
    /// When the answer is false, `failure` says why, if it is known.
    async accept({ expiresAt, now, isCurrent = () => true } = {}) {
      if (accepted) return true;
      if (claim) return claim;
      if (!value || record === null) return false;
      if (typeof locks?.request !== "function") {
        failure = "noLocks";
        return false;
      }
      if (!Number.isFinite(expiresAt) || !Number.isFinite(expiresAt + SKEW_SECONDS) ||
          (now !== undefined && !Number.isFinite(now))) {
        failure = "unavailable";
        return false;
      }
      claim = Promise.resolve().then(() => locks.request(LOCK, () => {
        // Recheck after waiting: a scenario or fragment may have changed, and
        // a token may have expired while another tab held the lock.
        const time = now ?? Date.now() / 1000;
        if (!isCurrent()) return false;
        if (time >= expiresAt + SKEW_SECONDS) {
          failure = "expired";
          return false;
        }
        if (storage.getItem(key) !== record) {
          failure = "replayed";
          return false;
        }
        const spent = spentNonces(storage, time);
        if (spent === null) {
          failure = "unavailable";
          return false;
        }
        if (spent.some((entry) => entry.nonce === value.nonce)) {
          failure = "replayed";
          return false;
        }
        // The nonce is marked spent before the record goes: if removing it
        // then fails, the request is lost, but nothing can be replayed.
        storage.setItem(SPENT_KEY, JSON.stringify([
          ...spent,
          { nonce: value.nonce, until: expiresAt + SKEW_SECONDS },
        ]));
        storage.removeItem(key);
        accepted = true;
        return true;
      })).catch(() => {
        failure = "unavailable";
        return accepted;
      });
      try { return await claim; }
      finally { claim = null; }
    },
  };
}

/// Writes the record of a new request under the lock claims take, so a write
/// never lands between a claim's check and its removal. `isCurrent` is asked
/// once the lock is taken: an edit overtaken by a newer one while it waited,
/// or a removal another tab has since followed with a newer request, writes
/// nothing. False when nothing was written — always, without locks.
export async function writePendingRequest(storage, key, locks, value, isCurrent) {
  if (typeof locks?.request !== "function") return false;
  try {
    return await locks.request(LOCK, () => {
      if (!isCurrent()) return false;
      storage.setItem(key, JSON.stringify(value));
      return true;
    });
  } catch { return false; }
}
