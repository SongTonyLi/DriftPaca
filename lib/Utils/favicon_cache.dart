import 'dart:async';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Persistent cache of website favicons keyed by *domain* (e.g.
/// `github.com`), so every URL under the same host shares one entry —
/// `https://github.com/a` and `https://github.com/b` resolve to the same
/// bytes, no per-URL bloat.
///
/// Two storage tiers:
///   1. **In-memory map** for the lifetime of the app — read synchronously
///      from the UI thread.
///   2. **Hive box `favicons`** for the lifetime of the install — opened
///      once at startup so `box.get`/`box.put` are sync after that.
///
/// On app restart the box rehydrates the on-disk bytes; cold starts no
/// longer pay a full round of network round-trips just to repaint
/// already-seen citations.
///
/// **Failure policy:** failed fetches are only marked in-memory, never
/// persisted. A transient Google outage would otherwise blacklist a
/// domain forever; with this policy the next launch retries the fetch.
class FaviconCache {
  FaviconCache._();
  static final FaviconCache instance = FaviconCache._();

  /// Shared client so repeated favicon fetches reuse a TLS connection to
  /// Google's favicon endpoint.
  static final http.Client _client = http.Client();

  static const Duration _fetchTimeout = Duration(seconds: 6);

  /// Box name to open at app startup via `Hive.openBox<Uint8List>(...)`.
  static const String boxName = 'favicons';

  Box<Uint8List>? _box;
  final Map<String, Uint8List?> _memory = {};
  final Map<String, Future<Uint8List?>> _inflight = {};

  /// Wire up the on-disk Hive box. Call once from `main()` after
  /// `Hive.initFlutter()` and before the first UI read.
  void attachBox(Box<Uint8List> box) {
    _box = box;
  }

  /// Returns Google's favicon endpoint for [domain] at 64px size — large
  /// enough to look crisp on Retina at 16-20 logical pixels.
  static String urlFor(String domain) =>
      'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(domain)}&sz=64';

  /// Synchronously returns cached bytes for [domain]. Checks the
  /// in-memory tier first, then the Hive box (also sync once opened).
  /// Returns `null` for "not present" or "marked failed in this session".
  Uint8List? bytesFor(String domain) {
    if (_memory.containsKey(domain)) return _memory[domain];
    final fromDisk = _box?.get(domain);
    if (fromDisk != null) {
      _memory[domain] = fromDisk;
      return fromDisk;
    }
    return null;
  }

  /// True if [domain] is known to either tier of the cache (success or
  /// in-session failure). Lets the UI skip the loading state when bytes
  /// are already locally resolvable.
  bool isResolved(String domain) {
    if (_memory.containsKey(domain)) return true;
    final box = _box;
    if (box != null && box.containsKey(domain)) return true;
    return false;
  }

  /// Fetches the favicon for [domain]. Resolution order:
  /// in-memory → Hive box → network. Concurrent calls for the same
  /// domain share one in-flight future.
  Future<Uint8List?> fetch(String domain) {
    if (domain.isEmpty) return Future.value(null);

    if (_memory.containsKey(domain)) return Future.value(_memory[domain]);

    final fromDisk = _box?.get(domain);
    if (fromDisk != null) {
      _memory[domain] = fromDisk;
      return Future.value(fromDisk);
    }

    final existing = _inflight[domain];
    if (existing != null) return existing;

    final future = _fetch(domain);
    _inflight[domain] = future;
    return future;
  }

  Future<Uint8List?> _fetch(String domain) async {
    try {
      final response =
          await _client.get(Uri.parse(urlFor(domain))).timeout(_fetchTimeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = response.bodyBytes;
        _memory[domain] = bytes;
        // Fire-and-forget persist so the next app launch hits Hive
        // instead of Google.
        _box?.put(domain, bytes);
        return bytes;
      }
    } catch (_) {
      // Fall through to in-memory failure marker below.
    } finally {
      _inflight.remove(domain);
    }
    // Don't persist failures — keep the door open for a retry next launch.
    _memory[domain] = null;
    return null;
  }

  /// Fire-and-forget preloading of multiple domains. Designed for the web
  /// search pipeline: kick off fetches as soon as result URLs are known so
  /// the bubble UI is hot by the time the assistant message renders.
  void preload(Iterable<String> domains) {
    for (final domain in domains) {
      if (domain.isEmpty) continue;
      fetch(domain); // ignore returned future — fire-and-forget
    }
  }

  /// Test-only reset.
  void clearForTest() {
    _memory.clear();
    _inflight.clear();
    _box = null;
  }
}
