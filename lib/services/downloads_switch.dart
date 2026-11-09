// Local patch (not upstream): app-wide switch to turn downloads off.
//
// Apple TV already hides every download entry point because it has no
// user-accessible storage. This reuses those same gates for a user setting
// (Settings -> Appearance -> Navigation -> Downloads), so a device that never
// downloads loses the sidebar entry, the download buttons, menu items and
// status icons. While off, sync rules don't run and queued downloads aren't
// resumed. Downloads already on the device are kept.

import '../utils/platform_detector.dart';
import 'settings_service.dart';

/// Whether downloads are shown and allowed: never on Apple TV, otherwise
/// unless the user turned them off.
bool downloadsEnabled() {
  if (PlatformDetector.isAppleTV()) return false;
  return SettingsService.instanceOrNull?.read(SettingsService.showDownloads) ?? true;
}
