/// HomeScreen — the single-page layout for Coco Downloader.
///
/// Implements a 3-zone design inside a [Scaffold]:
///   Zone 1 (top)    — [InputZone]: single/bulk link input with drag-and-drop.
///   Zone 2 (centre) — [FilterBar] + [PreviewTable]: expandable download queue.
///   Zone 3 (bottom) — [ActionBar]: save path, connections, progress, controls.
///
/// A [MenuBar] provides File / Settings / Help menus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../dialogs/about_dialog.dart';
import '../dialogs/add_magnet_dialog.dart';
import '../dialogs/add_page_dialog.dart';
import '../dialogs/add_torrent_dialog.dart';
import '../dialogs/help_dialog.dart';
import '../dialogs/ytdlp_dialog.dart';
import '../widgets/action_bar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/input_zone.dart';
import '../widgets/preview_table.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          _AppMenus(),
        ],
      ),
      body: const _HomeBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// _AppMenus — toolbar menu buttons
// ---------------------------------------------------------------------------

class _AppMenus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FileMenuButton(),
        _SettingsMenuButton(),
        _HelpMenuButton(),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _FileMenuButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FileAction>(
      tooltip: 'File',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('File'),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _FileAction.addTorrent,
          child: ListTile(
            leading: Icon(Icons.insert_drive_file_outlined),
            title: Text('Add Torrent...'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.addMagnet,
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Add Magnet...'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.addYtDlp,
          child: ListTile(
            leading: Icon(Icons.play_circle_outline),
            title: Text('Add via yt-dlp...'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.addPage,
          child: ListTile(
            leading: Icon(Icons.web),
            title: Text('Add from Page...'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _FileAction.history,
          child: ListTile(
            leading: Icon(Icons.history),
            title: Text('History'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _FileAction.exit,
          child: ListTile(
            leading: Icon(Icons.exit_to_app),
            title: Text('Exit'),
            dense: true,
          ),
        ),
      ],
      onSelected: (action) => _onFileAction(context, action),
    );
  }

  Future<void> _onFileAction(BuildContext context, _FileAction action) async {
    switch (action) {
      case _FileAction.addTorrent:
        await showAddTorrentDialog(context);
      case _FileAction.addMagnet:
        await showAddMagnetDialog(context);
      case _FileAction.addYtDlp:
        await showYtDlpDialog(context);
      case _FileAction.addPage:
        await showAddPageDialog(context);
      case _FileAction.history:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
        );
      case _FileAction.exit:
        // ignore: use_build_context_synchronously
        Navigator.of(context).maybePop();
    }
  }
}

enum _FileAction {
  addTorrent,
  addMagnet,
  addYtDlp,
  addPage,
  history,
  exit,
}

class _SettingsMenuButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      },
      child: const Text('Settings'),
    );
  }
}

class _HelpMenuButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_HelpAction>(
      tooltip: 'Help',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Help'),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _HelpAction.help,
          child: ListTile(
            leading: Icon(Icons.help_outline),
            title: Text('Help'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _HelpAction.about,
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            dense: true,
          ),
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _HelpAction.help:
            showHelpDialog(context);
          case _HelpAction.about:
            showAppAboutDialog(context);
        }
      },
    );
  }
}

enum _HelpAction { help, about }

// ---------------------------------------------------------------------------
// _HomeBody
// ---------------------------------------------------------------------------

/// Three-zone layout using a [Column].
///
/// Zone 2 is wrapped in [Expanded] so the preview table claims all remaining
/// vertical space after zones 1 and 3 have been laid out.
class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        // Zone 1 — Link input
        InputZone(),

        Divider(height: 1),

        // Zone 2 — Filter controls + preview table (takes all remaining space)
        FilterBar(),
        Expanded(
          child: PreviewTable(),
        ),

        Divider(height: 1),

        // Zone 3 — Action bar (path, connections, progress, buttons, log)
        ActionBar(),
      ],
    );
  }
}
