// Local patch (not upstream): auto-lock for PIN-protected profiles.
//
// When Plezy comes back after being away for at least [profileAutoLockGrace]
// while a PIN-protected profile is active, it drops to the most recently used
// unprotected profile instead of reopening the protected one without its PIN.
// "Away" covers both a warm resume (the process stayed alive) and a cold start
// (Android killed the process, or the TV restarted), so the time Plezy left the
// foreground is also persisted.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import 'profile.dart';

/// How long Plezy may sit in the background before a protected profile locks.
const profileAutoLockGrace = Duration(minutes: 5);

const _backgroundedAtKey = 'local_patch_auto_lock_backgrounded_at';

/// The profile to fall back to when [active] locks: the most recently used
/// profile without a PIN. Null when [active] is not PIN-protected or no
/// unprotected profile exists. [profiles] is the provider's merged list, which
/// is already sorted most-recently-used first.
Profile? autoLockFallbackProfile(List<Profile> profiles, Profile? active) {
  if (active == null || !active.isPinProtected) return null;
  for (final profile in profiles) {
    if (profile.id != active.id && !profile.isPinProtected) return profile;
  }
  return null;
}

/// Whether a protected profile should lock, given when Plezy left the
/// foreground. A missing timestamp means Plezy never recorded leaving (a crash,
/// a power cut, or the first launch with this patch), which locks.
bool autoLockGraceExpired(DateTime? backgroundedAt, DateTime now) =>
    backgroundedAt == null || now.difference(backgroundedAt) >= profileAutoLockGrace;

/// Persisted "left the foreground at" time, read by the cold-start path.
DateTime? readAutoLockBackgroundedAt(StorageService storage) {
  final ms = storage.readNullableInt(_backgroundedAtKey);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> clearAutoLockBackgroundedAt(StorageService storage) async {
  await storage.prefs.remove(_backgroundedAtKey);
}

/// Latches when the app leaves the foreground and, on the next `resumed`,
/// reports whether it was away for at least [grace].
///
/// Same shape as MainScreen's other resume gates: `inactive`-only overlays
/// never latch, the earliest backgrounded time wins, and a session that keeps
/// playing in Picture in Picture never left the user's sight. The backgrounded
/// time is also written through [persist] so a cold start can apply the same
/// rule after Android kills the process.
class ProfileAutoLockResumeGate {
  ProfileAutoLockResumeGate({this.grace = profileAutoLockGrace, DateTime Function()? now, this.persist})
    : _now = now ?? DateTime.now;

  final Duration grace;
  final DateTime Function() _now;

  /// Records the backgrounded time (null clears it) for the cold-start path.
  final void Function(DateTime? backgroundedAt)? persist;

  DateTime? _backgroundedAt;

  bool consumeLockOn(AppLifecycleState state, {bool pipContinuation = false}) {
    switch (state) {
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (backgroundedAt != null) persist?.call(null);
        return backgroundedAt != null && _now().difference(backgroundedAt) >= grace;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (pipContinuation || _backgroundedAt != null) return false;
        final at = _now();
        _backgroundedAt = at;
        persist?.call(at);
        return false;
      case AppLifecycleState.inactive:
        return false;
    }
  }
}

/// Persist callback for [ProfileAutoLockResumeGate] backed by [StorageService].
void persistAutoLockBackgroundedAt(DateTime? at) {
  unawaited(() async {
    try {
      final storage = await StorageService.getInstance();
      if (at == null) {
        await storage.prefs.remove(_backgroundedAtKey);
      } else {
        await storage.prefs.setInt(_backgroundedAtKey, at.millisecondsSinceEpoch);
      }
    } catch (e, st) {
      appLogger.w('Auto-lock: failed to persist backgrounded time', error: e, stackTrace: st);
    }
  }());
}
