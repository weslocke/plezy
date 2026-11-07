import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_auto_lock.dart';

Profile _local(String id, {bool pin = false}) => Profile.local(
  id: id,
  displayName: id,
  pinHash: pin ? computePinHash('1234') : null,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('autoLockFallbackProfile', () {
    final locked = _local('locked', pin: true);

    test('picks the most recently used unprotected profile', () {
      // The provider's list is already sorted most-recently-used first.
      final profiles = [locked, _local('kids'), _local('guest'), _local('other-locked', pin: true)];

      expect(autoLockFallbackProfile(profiles, locked)?.id, 'kids');
    });

    test('skips protected profiles, including protected Plex Home users', () {
      final protectedHome = Profile.plexHome(
        id: 'plex-home-a-b',
        displayName: 'Home',
        plexProtected: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final profiles = [locked, protectedHome, _local('open')];

      expect(autoLockFallbackProfile(profiles, locked)?.id, 'open');
    });

    test('does nothing when the active profile has no PIN', () {
      final open = _local('open');

      expect(autoLockFallbackProfile([open, _local('other')], open), isNull);
    });

    test('does nothing when there is no unprotected profile to fall back to', () {
      expect(autoLockFallbackProfile([locked, _local('b', pin: true)], locked), isNull);
    });

    test('does nothing without an active profile', () {
      expect(autoLockFallbackProfile([_local('open')], null), isNull);
    });
  });

  group('autoLockGraceExpired', () {
    final now = DateTime(2026, 11, 7, 12);

    test('locks after the five minute grace period', () {
      expect(autoLockGraceExpired(now.subtract(const Duration(minutes: 5)), now), isTrue);
      expect(autoLockGraceExpired(now.subtract(const Duration(minutes: 4, seconds: 59)), now), isFalse);
    });

    test('locks when no backgrounded time was recorded', () {
      expect(autoLockGraceExpired(null, now), isTrue);
    });
  });

  group('ProfileAutoLockResumeGate', () {
    late DateTime now;
    late List<DateTime?> persisted;
    late ProfileAutoLockResumeGate gate;

    setUp(() {
      now = DateTime(2026, 11, 7, 12);
      persisted = [];
      gate = ProfileAutoLockResumeGate(now: () => now, persist: persisted.add);
    });

    test('locks on resume after the grace period', () {
      gate.consumeLockOn(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 6));

      expect(gate.consumeLockOn(AppLifecycleState.resumed), isTrue);
      expect(persisted, [DateTime(2026, 11, 7, 12), null]);
    });

    test('does not lock on a short trip out of the app', () {
      gate.consumeLockOn(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 2));

      expect(gate.consumeLockOn(AppLifecycleState.resumed), isFalse);
    });

    test('keeps the earliest backgrounded time across hidden/paused churn', () {
      gate.consumeLockOn(AppLifecycleState.hidden);
      now = now.add(const Duration(minutes: 4));
      gate.consumeLockOn(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 2));

      expect(gate.consumeLockOn(AppLifecycleState.resumed), isTrue);
      expect(persisted.first, DateTime(2026, 11, 7, 12));
    });

    test('ignores inactive-only overlays and a first resume', () {
      expect(gate.consumeLockOn(AppLifecycleState.resumed), isFalse);
      gate.consumeLockOn(AppLifecycleState.inactive);
      now = now.add(const Duration(hours: 1));

      expect(gate.consumeLockOn(AppLifecycleState.resumed), isFalse);
      expect(persisted, isEmpty);
    });

    test('does not lock while playback continues in Picture in Picture', () {
      gate.consumeLockOn(AppLifecycleState.paused, pipContinuation: true);
      now = now.add(const Duration(hours: 1));

      expect(gate.consumeLockOn(AppLifecycleState.resumed), isFalse);
    });
  });
}
