/// Rewinds a reveal cursor by one code unit when it lands between the two
/// halves of a UTF-16 surrogate pair, so [String.substring] never emits an
/// orphaned high surrogate (which renders as a tofu box for one frame).
///
/// Shared by every typewriter reveal in the app: the assistant bubble's
/// markdown reveal and `TokenRevealText`'s plain-text one both walk a
/// character cursor forward through a string that is still growing, and both
/// can land mid-pair either because the cursor stopped there or because the
/// target itself ends mid-pair (a stream chunk split across a code point).
int surrogateSafeLength(String text, int length) {
  if (length <= 0) return length;
  final safe = length > text.length ? text.length : length;
  if (safe <= 0) return safe;
  final unit = text.codeUnitAt(safe - 1);
  // A high surrogate (0xD800–0xDBFF) as the last included unit leaves its low
  // half outside the cut — whether the low half exists further along (a
  // mid-reveal boundary) or the target itself ends mid-pair. Cut before the
  // high surrogate in both cases.
  return (unit >= 0xD800 && unit <= 0xDBFF) ? safe - 1 : safe;
}
