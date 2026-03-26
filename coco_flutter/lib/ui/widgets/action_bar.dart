/// ActionBar — bottom action zone with save path, connections, progress,
/// status, buttons, and the collapsible log panel.
///
/// Row 1: Save-to path TextField + Browse button.
/// Row 2: Connections + Splits compact fields.
/// Progress bar ([SquareProgressBar]).
/// Status row ([GlobalStatusBar]).
/// Button row: Pause | Cancel | spacer | Download.
/// Log panel ([LogPanel]).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/preview_provider.dart';
import 'global_status_bar.dart';
import 'log_panel.dart';
import 'progress_bar.dart';

// ---------------------------------------------------------------------------
// ActionBar
// ---------------------------------------------------------------------------

class ActionBar extends ConsumerStatefulWidget {
  const ActionBar({super.key});

  @override
  ConsumerState<ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<ActionBar> {
  late final TextEditingController _outdirController;
  late final TextEditingController _connController;
  late final TextEditingController _splitController;

  // Track whether controllers have been seeded from config.
  bool _initialised = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _outdirController = TextEditingController();
    _connController = TextEditingController();
    _splitController = TextEditingController();
  }

  @override
  void dispose() {
    _outdirController.dispose();
    _connController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  /// Seed text controllers once from the loaded config (avoids overwriting
  /// user edits on every rebuild).
  void _maybeInitControllers(
    String outdir,
    int connections,
    int splits,
  ) {
    if (_initialised) return;
    _outdirController.text = outdir;
    _connController.text = connections.toString();
    _splitController.text = splits.toString();
    _initialised = true;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _browse() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select download folder',
    );
    if (result != null) {
      _outdirController.text = result;
      ref
          .read(configProvider.notifier)
          .updateConfig((c) => c.copyWith(outdir: result));
    }
  }

  void _onOutdirSubmitted(String value) {
    ref
        .read(configProvider.notifier)
        .updateConfig((c) => c.copyWith(outdir: value));
  }

  void _onConnectionsChanged(String value) {
    final v = int.tryParse(value);
    if (v != null && v > 0) {
      ref
          .read(configProvider.notifier)
          .updateConfig((c) => c.copyWith(connections: v));
    }
  }

  void _onSplitsChanged(String value) {
    final v = int.tryParse(value);
    if (v != null && v > 0) {
      ref
          .read(configProvider.notifier)
          .updateConfig((c) => c.copyWith(splits: v));
    }
  }

  Future<void> _startDownload() async {
    final cfg = ref.read(configProvider);
    final items = ref.read(previewProvider).items;

    await ref.read(downloadProvider.notifier).startDownload(
          items: items,
          outdir: cfg.outdir.isEmpty ? '.' : cfg.outdir,
          connections: cfg.connections,
          splits: cfg.splits,
          concurrent: cfg.concurrency,
          httpProxy: cfg.httpProxy.isEmpty ? null : cfg.httpProxy,
          httpsProxy: cfg.httpsProxy.isEmpty ? null : cfg.httpsProxy,
          aria2Path: cfg.aria2Path,
          autoCategorize: cfg.autoCategorize,
          categoryExts:
              cfg.categoryExts.isEmpty ? null : cfg.categoryExts,
          categoryFolders:
              cfg.categoryFolders.isEmpty ? null : cfg.categoryFolders,
        );
  }

  Future<void> _pauseOrResume() async {
    final dl = ref.read(downloadProvider);
    if (dl.isPaused) {
      await ref.read(downloadProvider.notifier).resume();
    } else {
      await ref.read(downloadProvider.notifier).pause();
    }
  }

  Future<void> _cancel() async {
    await ref.read(downloadProvider.notifier).cancel();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final dl = ref.watch(downloadProvider);
    final previewState = ref.watch(previewProvider);
    final cs = Theme.of(context).colorScheme;

    _maybeInitControllers(cfg.outdir, cfg.connections, cfg.splits);

    final hasSelected =
        previewState.items.any((i) => i.selected && !i.excluded);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------------------------------------------------------------
              // Row 1: Save-to path + Browse
              // ---------------------------------------------------------------
              Row(
                children: [
                  const SizedBox(
                    width: 72,
                    child: Text('Save to:', textAlign: TextAlign.right),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _outdirController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: _onOutdirSubmitted,
                      onEditingComplete: () =>
                          _onOutdirSubmitted(_outdirController.text),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: _browse,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Browse…'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // ---------------------------------------------------------------
              // Row 2: Connections + Splits
              // ---------------------------------------------------------------
              Row(
                children: [
                  const SizedBox(
                    width: 72,
                    child: Text(
                      'Connections:',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _connController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onSubmitted: _onConnectionsChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('Splits:', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _splitController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onSubmitted: _onSplitsChanged,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ---------------------------------------------------------------
              // Progress bar
              // ---------------------------------------------------------------
              SquareProgressBar(value: dl.overallPercent),

              const SizedBox(height: 4),

              // ---------------------------------------------------------------
              // Status row
              // ---------------------------------------------------------------
              const GlobalStatusBar(),

              const SizedBox(height: 8),

              // ---------------------------------------------------------------
              // Button row
              // ---------------------------------------------------------------
              Row(
                children: [
                  // Pause / Resume
                  OutlinedButton.icon(
                    onPressed: dl.isRunning ? _pauseOrResume : null,
                    icon: Icon(
                      dl.isPaused ? Icons.play_arrow : Icons.pause,
                      size: 18,
                    ),
                    label: Text(dl.isPaused ? 'Resume' : 'Pause'),
                  ),
                  const SizedBox(width: 8),

                  // Cancel
                  OutlinedButton.icon(
                    onPressed: dl.isRunning ? _cancel : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withAlpha(160)),
                    ),
                  ),

                  const Spacer(),

                  // Download (prominent / filled)
                  FilledButton.icon(
                    onPressed:
                        (!dl.isRunning && hasSelected) ? _startDownload : null,
                    icon: dl.isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download, size: 20),
                    label: Text(
                      dl.isRunning ? 'Downloading…' : 'Download',
                      style: const TextStyle(fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),
            ],
          ),
        ),

        // -------------------------------------------------------------------
        // Log panel (collapsible)
        // -------------------------------------------------------------------
        const Divider(height: 1),
        const LogPanel(),
      ],
    );
  }
}
