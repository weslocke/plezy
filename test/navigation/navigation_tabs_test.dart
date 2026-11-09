import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/services/downloads_switch.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  group('NavigationTab.resolveDefaultTab', () {
    test('offline prefers Downloads when available', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, hasLiveTv: false, preferredStartup: null),
        NavigationTabId.downloads,
      );
    });

    test('offline ignores an online-only preferred section', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, hasLiveTv: true, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.downloads,
      );
    });

    test('online honours the preferred section when it is visible', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: true, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.liveTv,
      );
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.search),
        NavigationTabId.search,
      );
    });

    test('online falls back to Home when preferred Live TV is unavailable', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.liveTv),
        NavigationTabId.discover,
      );
    });

    test('online defaults to Home when no preference is set', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: true, preferredStartup: null),
        NavigationTabId.discover,
      );
    });

    test('online falls back to Home when preferred Explore is unavailable', () {
      expect(
        NavigationTab.resolveDefaultTab(isOffline: false, hasLiveTv: false, preferredStartup: NavigationTabId.explore),
        NavigationTabId.discover,
      );
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: false,
          hasExplore: true,
          preferredStartup: NavigationTabId.explore,
        ),
        NavigationTabId.explore,
      );
    });
  });

  group('NavigationTab.getVisibleTabs', () {
    test('hides Explore until a catalog source is connected', () {
      final without = NavigationTab.getVisibleTabs(isOffline: false);
      expect(without.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));

      final with_ = NavigationTab.getVisibleTabs(isOffline: false, hasExplore: true, hasLiveTv: true);
      final ids = with_.map((tab) => tab.id).toList();
      expect(ids, contains(NavigationTabId.explore));
      // Explore sits after Live TV, directly before Search.
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.liveTv) + 1);
      expect(ids.indexOf(NavigationTabId.explore), ids.indexOf(NavigationTabId.search) - 1);
    });

    test('Explore is online-only', () {
      final offline = NavigationTab.getVisibleTabs(isOffline: true, hasExplore: true);
      expect(offline.map((tab) => tab.id), isNot(contains(NavigationTabId.explore)));
    });
  });

  // Local patch: the app-wide downloads switch (lib/services/downloads_switch.dart).
  group('downloads switch', () {
    setUp(resetSharedPreferencesForTest);

    bool hasDownloadsTab({required bool isOffline}) =>
        NavigationTab.getVisibleTabs(isOffline: isOffline).any((t) => t.id == NavigationTabId.downloads);

    test('downloads are on by default', () async {
      await SettingsService.getInstance();
      expect(downloadsEnabled(), isTrue);
      expect(hasDownloadsTab(isOffline: false), isTrue);
      expect(hasDownloadsTab(isOffline: true), isTrue);
    });

    test('turning downloads off removes the Downloads tab', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.showDownloads, false);
      expect(downloadsEnabled(), isFalse);
      expect(hasDownloadsTab(isOffline: false), isFalse);
      expect(hasDownloadsTab(isOffline: true), isFalse);
    });

    test('offline without downloads opens Settings instead of Downloads', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.showDownloads, false);
      expect(
        NavigationTab.resolveDefaultTab(isOffline: true, hasLiveTv: false, preferredStartup: NavigationTabId.downloads),
        NavigationTabId.settings,
      );
    });
  });
}
