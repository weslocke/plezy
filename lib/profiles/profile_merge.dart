import '../connection/connection.dart';
import '../models/plex/plex_home_user.dart';
import '../services/storage_service.dart';
import 'profile.dart';
import 'profile_connection.dart';

/// Groups profile-connection rows by profile id, preserving input order.
Map<String, List<ProfileConnection>> groupConnectionsByProfile(List<ProfileConnection> pcs) {
  final out = <String, List<ProfileConnection>>{};
  for (final pc in pcs) {
    out.putIfAbsent(pc.profileId, () => []).add(pc);
  }
  return out;
}

/// Join-table rows that should be shown as explicit, user-manageable
/// connections for [profile].
///
/// Plex Home profiles own their parent account implicitly through
/// [Profile.parentConnectionId]. A parent [ProfileConnection] row may still
/// exist as a token cache, but UI should not render it as a removable
/// borrowed connection.
List<ProfileConnection> visibleProfileConnections(Profile profile, List<ProfileConnection> pcs) {
  final parentId = profile.parentConnectionId;
  if (!profile.isPlexHome || parentId == null) return pcs;
  return pcs.where((pc) => pc.connectionId != parentId).toList();
}

/// Merge local profiles with virtual Plex Home profiles. Each Plex Home
/// user becomes a virtual profile attached to its `connectionId`. Home
/// users whose connection isn't registered are dropped — their profile
/// can't be activated until the parent account is re-added.
List<Profile> mergeLocalWithPlexHome({
  required List<Profile> locals,
  required Map<String, List<PlexHomeUser>> plexHomeByConnectionId,
  required Map<String, Connection> connectionsById,
  StorageService? storage,
}) {
  final out = <Profile>[for (final local in locals) _withLatestStoredLastUsed(local, storage)];
  for (final entry in plexHomeByConnectionId.entries) {
    final connectionId = entry.key;
    if (!connectionsById.containsKey(connectionId)) continue;
    for (final user in entry.value) {
      out.add(
        Profile.virtualPlexHome(
          connectionId: connectionId,
          homeUser: user,
          lastUsedAt: storage?.getProfileLastUsed(
            plexHomeProfileId(accountConnectionId: connectionId, homeUserUuid: user.uuid),
          ),
        ),
      );
    }
  }
  return sortProfilesByLastUsed(out);
}

/// Local patch (not upstream): drop virtual Plex Home profiles whose Home user
/// is attached to a PIN-protected local profile.
///
/// Every Home user of a signed-in Plex account surfaces as its own profile,
/// gated only by Plex's own PIN. An account that merely has servers shared to
/// it has no Plex Home and so cannot set one, which would leave the account
/// reachable without the PIN of the local profile that was meant to guard it.
/// Hiding the virtual profile leaves the PIN-protected local profile as the
/// only way in, both in the picker and as a borrow source.
List<Profile> hidePlexHomeProfilesGuardedByLocalPin(List<Profile> profiles, Iterable<ProfileConnection> connections) {
  final pinProtectedLocalIds = {
    for (final p in profiles)
      if (p.isLocal && p.isPinProtected) p.id,
  };
  if (pinProtectedLocalIds.isEmpty) return profiles;
  final guarded = {
    for (final pc in connections)
      if (pinProtectedLocalIds.contains(pc.profileId) && pc.userIdentifier.isNotEmpty)
        '${pc.connectionId}/${pc.userIdentifier}',
  };
  if (guarded.isEmpty) return profiles;
  return [
    for (final p in profiles)
      if (!(p.isPlexHome && guarded.contains('${p.parentConnectionId}/${p.plexHomeUserUuid}'))) p,
  ];
}

List<Profile> sortProfilesByLastUsed(List<Profile> profiles) {
  final indexed = profiles.indexed.toList();
  indexed.sort((a, b) {
    final aLastUsed = a.$2.lastUsedAt;
    final bLastUsed = b.$2.lastUsedAt;
    if (aLastUsed == null && bLastUsed == null) return a.$1.compareTo(b.$1);
    if (aLastUsed == null) return 1;
    if (bLastUsed == null) return -1;
    final byLastUsed = bLastUsed.compareTo(aLastUsed);
    if (byLastUsed != 0) return byLastUsed;
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

Profile _withLatestStoredLastUsed(Profile profile, StorageService? storage) {
  final storedLastUsed = storage?.getProfileLastUsed(profile.id);
  final currentLastUsed = profile.lastUsedAt;
  final lastUsedAt = switch ((currentLastUsed, storedLastUsed)) {
    (null, final stored?) => stored,
    (final current?, null) => current,
    (final current?, final stored?) => stored.isAfter(current) ? stored : current,
    _ => null,
  };
  if (lastUsedAt == currentLastUsed) return profile;
  return profile.copyWith(lastUsedAt: lastUsedAt);
}
