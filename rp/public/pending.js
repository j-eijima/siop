// The record of the request this browser sent, and the rule that one response
// — and only one — is accepted for it. Kept apart from the page so the rule
// can be tested under Node.

/// `storage` is localStorage, or anything with its getItem and removeItem.
export function pendingRequest(storage, key) {
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
    /// Removing the record is not enough on its own — two tabs that read it
    /// before either finished verifying would both show success — so the
    /// claim is what decides acceptance. One response authenticates; a
    /// second, however valid, is a replay.
    accept() {
      if (accepted) return true;
      if (record === null || storage.getItem(key) !== record) return false;
      storage.removeItem(key);
      accepted = true;
      return true;
    },
  };
}
