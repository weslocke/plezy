// Local patch (not upstream): per-profile on/off switch for Plex servers.
// See lib/profiles/server_disable.dart.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/server_disable.dart';
import '../../services/plex_auth_service.dart' show PlexServer;
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

/// The Plex servers the active profile can reach, from the cached server list
/// of each Plex account it uses. Cached so turned-off servers stay listed.
List<PlexServer> serversForActiveProfile(ActiveProfileProvider provider) {
  final profile = provider.active;
  if (profile == null) return const [];
  final accountIds = <String>{
    ?profile.parentConnectionId,
    for (final pc in provider.connectionsByProfile[profile.id] ?? const []) pc.connectionId,
  };
  final byId = <String, PlexServer>{};
  for (final id in accountIds) {
    if (provider.connectionsById[id] case final PlexAccountConnection account) {
      for (final server in account.servers) {
        byId.putIfAbsent(server.clientIdentifier, () => server);
      }
    }
  }
  final servers = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return servers;
}

class ServerToggleScreen extends StatefulWidget {
  const ServerToggleScreen({super.key});

  @override
  State<ServerToggleScreen> createState() => _ServerToggleScreenState();
}

class _ServerToggleScreenState extends State<ServerToggleScreen> {
  Set<String>? _disabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final profileId = context.read<ActiveProfileProvider>().activeId;
    if (profileId == null) {
      _disabled = {};
    } else {
      disabledServerIdsFor(profileId).then((ids) {
        if (mounted) setState(() => _disabled = ids);
      });
    }
  }

  Future<void> _toggle(String profileId, List<PlexServer> servers, PlexServer server, bool on) async {
    final disabled = _disabled;
    if (disabled == null || _busy) return;
    if (!on) {
      final remaining = servers.where((s) => s.clientIdentifier != server.clientIdentifier);
      if (remaining.every((s) => disabled.contains(s.clientIdentifier))) {
        showErrorSnackBar(context, 'At least one server has to stay on.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await setServerDisabled(profileId, server.clientIdentifier, disabled: !on);
      final next = await disabledServerIdsFor(profileId);
      if (!mounted) return;
      setState(() => _disabled = next);
      // Rebind so the change takes effect now: a turned-off server is
      // disconnected, a turned-on one is connected.
      await context.read<ActiveProfileBinder>().rebindActive();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActiveProfileProvider>();
    final profileId = provider.activeId;
    final servers = serversForActiveProfile(provider);
    final disabled = _disabled;
    final theme = Theme.of(context);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(
          'Servers turned off here are never contacted by this profile: they are '
          'skipped at startup, in search and on the home screen. Other profiles are not affected.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ];

    if (profileId == null || disabled == null) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (servers.isEmpty) {
      children.add(
        const SettingsGroup(
          title: 'Plex servers',
          children: [ListTile(title: Text('This profile has no Plex servers.'))],
        ),
      );
    } else {
      children.add(
        SettingsGroup(
          title: 'Plex servers',
          children: [
            for (final server in servers)
              FocusableSwitchListTile(
                key: ValueKey('server-toggle-${server.clientIdentifier}'),
                secondary: const AppIcon(Symbols.dns_rounded, fill: 1),
                title: Text(server.name),
                subtitle: Text(server.owned ? 'Your server' : 'Shared with you'),
                value: !disabled.contains(server.clientIdentifier),
                onChanged: _busy ? null : (on) => _toggle(profileId, servers, server, on),
              ),
          ],
        ),
      );
    }
    children.add(const SizedBox(height: 24));

    return SettingsPage(title: const Text('Servers'), children: children);
  }
}
