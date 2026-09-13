// The record of the request this browser sent, and the rule that one response
// — and only one — is accepted for it. Kept apart from the page so the rule
// can be tested under Node.

/// The lock every tab of this origin takes to claim the request.
const LOCK = "siop-rp.pending-request";

/// `storage` is localStorage, or anything with its getItem and removeItem.
/// `locks` is navigator.locks, or anything with its request(name, callback).
export function pendingRequest(storage, key, locks) {
  const record = storage.getItem(key);
  let accepted = false;

  return {
    /// What was sent, or null when this browser has no record of it.
    value: JSON.parse(record ?? "null"),

    /// Claims the request for a response that has passed every check.
    ///
    /// True for the page that claims it first, and again whenever that page
    /// asks. False for any other page: the record is gone because another tab
    /// accepted a response to it, or it has been replaced by a newer request.
    /// One response authenticates; a second, however valid, is a replay.
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
        storage.removeItem(key);
        return true;
      });
      return accepted;
    },
  };
}
