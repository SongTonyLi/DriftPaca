import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks whether the user has interacted recently. Any [poke] keeps/returns the
/// screen to active and (re)arms a one-shot idle timer; when that timer fires
/// the screen goes inactive. Listeners are notified **only on transitions**
/// (active <-> inactive), never on every poke, so continuous interaction does
/// not spam rebuilds.
class IdleActivityController extends ChangeNotifier {
  IdleActivityController({
    this.idleAfter = const Duration(seconds: 4),
    Timer Function(Duration, void Function())? createTimer,
  }) : _createTimer = createTimer ?? Timer.new {
    _arm();
  }

  final Duration idleAfter;
  final Timer Function(Duration, void Function()) _createTimer;

  bool _isActive = true;
  bool get isActive => _isActive;

  Timer? _timer;

  void _arm() {
    _timer?.cancel();
    _timer = _createTimer(idleAfter, _onIdle);
  }

  void _onIdle() {
    if (!_isActive) return;
    _isActive = false;
    notifyListeners();
  }

  /// Record user activity: return to / stay active and restart the countdown.
  void poke() {
    _arm();
    if (!_isActive) {
      _isActive = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
