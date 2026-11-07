// Local patch (not upstream): make search honour hidden libraries even when
// the server's search rows cannot be matched to a library.
//
// Search drops a row only when its `librarySectionID` matches a hidden
// library, and deliberately keeps rows it cannot attribute to any library.
// On some servers (seen with servers shared to the account) search rows for
// hidden libraries come back unfiltered. This scope closes the gap from the
// library list the profile already has:
//
// - servers whose every library is hidden are not searched at all, which is
//   also faster;
// - a row with no library on a server where every library of that row's kind
//   (movies, TV, or music) is hidden is dropped.

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';

enum _KindGroup { movie, show, music, any }

_KindGroup? _groupForLibrary(MediaKind kind) => switch (kind) {
  MediaKind.movie => _KindGroup.movie,
  MediaKind.show || MediaKind.season || MediaKind.episode => _KindGroup.show,
  MediaKind.artist || MediaKind.album || MediaKind.track => _KindGroup.music,
  // Photo libraries never produce search rows Plezy shows.
  MediaKind.photo => null,
  // Mixed or unrecognised libraries could hold anything.
  _ => _KindGroup.any,
};

_KindGroup? _groupForItem(MediaKind kind) => switch (kind) {
  MediaKind.movie => _KindGroup.movie,
  MediaKind.show || MediaKind.season || MediaKind.episode => _KindGroup.show,
  MediaKind.artist || MediaKind.album || MediaKind.track => _KindGroup.music,
  _ => null,
};

class HiddenLibrarySearchScope {
  HiddenLibrarySearchScope._(this.fullyHiddenServerIds, this._visibleGroupsByServer);

  /// Builds the scope from the profile's [libraries] and [hiddenLibraryKeys]
  /// (global `serverId:libraryId` keys). Servers with no loaded libraries are
  /// left alone: there is nothing to decide from.
  factory HiddenLibrarySearchScope.from(List<MediaLibrary> libraries, Set<String> hiddenLibraryKeys) {
    final visibleGroups = <String, Set<_KindGroup>>{};
    final serversWithLibraries = <String>{};
    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId == null) continue;
      serversWithLibraries.add(serverId);
      final groups = visibleGroups.putIfAbsent(serverId, () => <_KindGroup>{});
      if (hiddenLibraryKeys.contains(library.globalKey)) continue;
      final group = _groupForLibrary(library.kind);
      if (group != null) groups.add(group);
    }
    final fullyHidden = {
      for (final serverId in serversWithLibraries)
        if (libraries.every((l) => l.serverId != serverId || hiddenLibraryKeys.contains(l.globalKey))) serverId,
    };
    return HiddenLibrarySearchScope._(fullyHidden, visibleGroups);
  }

  /// Servers whose every library is hidden; search skips them.
  final Set<String> fullyHiddenServerIds;

  final Map<String, Set<_KindGroup>> _visibleGroupsByServer;

  /// Whether a row that could not be matched to a library should be kept.
  bool keepsUnattributed(MediaItem item) {
    final serverId = item.serverId;
    if (serverId == null) return true;
    if (fullyHiddenServerIds.contains(serverId)) return false;
    final visible = _visibleGroupsByServer[serverId];
    if (visible == null || visible.contains(_KindGroup.any)) return true;
    final group = _groupForItem(item.kind);
    if (group == null) return true;
    return visible.contains(group);
  }
}
