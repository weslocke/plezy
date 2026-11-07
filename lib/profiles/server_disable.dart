// Local patch (not upstream): per-profile switch to turn off Plex servers.
//
// A Plex account brings every server shared to it, and binding a profile
// connects to all of them and waits for each before the home screen loads. A
// turned-off server is left out of the bind entirely: it is never contacted,
// never searched, and never waited on. It stays listed in the Servers settings
// screen (from the account's cached server list) so it can be turned back on.

import '../services/plex_auth_service.dart' show PlexServer;
import '../services/storage_service.dart';

const _keyPrefix = 'local_patch_disabled_servers_';

/// Server machine ids turned off for [profileId].
Future<Set<String>> disabledServerIdsFor(String profileId) async {
  final storage = await StorageService.getInstance();
  return (storage.prefs.getStringList('$_keyPrefix$profileId') ?? const <String>[]).toSet();
}

Future<void> setServerDisabled(String profileId, String serverId, {required bool disabled}) async {
  final storage = await StorageService.getInstance();
  final next = await disabledServerIdsFor(profileId);
  disabled ? next.add(serverId) : next.remove(serverId);
  if (next.isEmpty) {
    await storage.prefs.remove('$_keyPrefix$profileId');
  } else {
    await storage.prefs.setStringList('$_keyPrefix$profileId', next.toList()..sort());
  }
}

/// The ids from [disabled] that apply to [serverIds]. A profile can never
/// switch off every server it has: if [disabled] would leave nothing, it is
/// ignored, so the profile still binds instead of landing on an empty screen.
Set<String> effectiveDisabledServerIds(Iterable<String> serverIds, Set<String> disabled) {
  if (disabled.isEmpty) return const {};
  final ids = serverIds.toSet();
  if (ids.isEmpty || ids.every(disabled.contains)) return const {};
  return ids.intersection(disabled);
}

/// [servers] without the ones turned off (see [effectiveDisabledServerIds]).
List<PlexServer> withoutDisabledServers(List<PlexServer> servers, Set<String> disabled) {
  final off = effectiveDisabledServerIds(servers.map((s) => s.clientIdentifier), disabled);
  if (off.isEmpty) return servers;
  return [
    for (final server in servers)
      if (!off.contains(server.clientIdentifier)) server,
  ];
}
