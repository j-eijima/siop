// The record of the request this browser sent, and the rule that one response
// — and only one — is accepted for it. Kept apart from the page so the rule
// can be tested under Node.

/// The lock every tab of this origin takes to claim the request.
const LOCK = "siop-rp.pending-request";

/// Nonces already accepted, newest last. A replay can only pass while its
/// token is unexpired, so the last few are what matter; fifty covers any
/// replay within a token's lifetime unless far more requests than that are
/// made first, which a test RP does not see.
const SPENT_KEY = "siop-rp.spent-nonces";
const SPENT_KEPT = 50;

function spentNonces(storage) {
  try {
    return JSON.parse(storage.getItem(SPENT_KEY) ?? "[]");
  } catch {
    return [];
  }
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

    /// Claims the request for a response that has passed every check.
    ///
    /// True for the page that claims it first, and again whenever that page
    /// asks. False for any other page: the record is gone because another tab
    /// accepted a response to it, it has been replaced by a newer request, or
    /// its nonce has been accepted before. One response authenticates; a
    /// second, however valid, is a replay.
    ///
    /// Finding the record and removing it happen under a lock every tab of
    /// this origin shares. localStorage has no compare-and-remove of its own,
    /// so without the lock two tabs could both find the record and both
    /// remove it. A browser that offers no locks cannot make that promise,
    /// and accepts nothing.
    async accept() {
      if (accepted) return true;
      if (record === null || !locks) return false;
      accepted = await locks.request(LOCK, () => {
        if (storage.getItem(key) !== record) return false;
        // A record can come back after it was used — written again by a
        // request page left open, say. The nonce is what makes a request
        // one-shot, so a nonce accepted once is never accepted again.
        const spent = spentNonces(storage);
        if (spent.includes(value.nonce)) return false;
        storage.removeItem(key);
        storage.setItem(SPENT_KEY, JSON.stringify([...spent, value.nonce].slice(-SPENT_KEPT)));
        return true;
      });
      return accepted;
    },
  };
}
