import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/services/hidden_library_search_scope.dart';

import '../test_helpers/media_items.dart';

MediaLibrary _lib(String server, String id, MediaKind kind) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: '$server $id', kind: kind, serverId: ServerId(server));

MediaItem _row(String server, MediaKind kind) =>
    testMediaItem(id: '$server-${kind.name}', backend: MediaBackend.plex, kind: kind, title: 'x', serverId: server);

void main() {
  final libraries = [
    _lib('tower', '1', MediaKind.movie),
    _lib('tower', '2', MediaKind.show),
    _lib('tower', '3', MediaKind.artist),
    _lib('friend', '1', MediaKind.movie),
    _lib('friend', '2', MediaKind.artist),
    _lib('mixed', '1', MediaKind.unknown),
    _lib('mixed', '2', MediaKind.artist),
  ];

  test('a server counts as fully hidden only when every library is hidden', () {
    final scope = HiddenLibrarySearchScope.from(libraries, {'friend:1', 'friend:2', 'tower:3'});

    expect(scope.fullyHiddenServerIds, {'friend'});
  });

  test('unattributed rows follow the visible library kinds on their server', () {
    final scope = HiddenLibrarySearchScope.from(libraries, {'tower:3', 'mixed:2'});

    expect(scope.keepsUnattributed(_row('tower', MediaKind.album)), isFalse);
    expect(scope.keepsUnattributed(_row('tower', MediaKind.track)), isFalse);
    expect(scope.keepsUnattributed(_row('tower', MediaKind.movie)), isTrue);
    expect(scope.keepsUnattributed(_row('tower', MediaKind.episode)), isTrue);
    // A visible mixed library could hold anything.
    expect(scope.keepsUnattributed(_row('mixed', MediaKind.album)), isTrue);
  });

  test('rows from servers with no loaded libraries are kept', () {
    final scope = HiddenLibrarySearchScope.from(libraries, {'tower:3'});

    expect(scope.keepsUnattributed(_row('unknown-server', MediaKind.album)), isTrue);
    expect(scope.fullyHiddenServerIds, isEmpty);
  });

  test('rows of kinds outside movies, TV and music are kept', () {
    final scope = HiddenLibrarySearchScope.from(libraries, {'tower:1', 'tower:2', 'tower:3'});

    expect(scope.fullyHiddenServerIds, {'tower'});
    expect(scope.keepsUnattributed(_row('friend', MediaKind.collection)), isTrue);
  });
}
