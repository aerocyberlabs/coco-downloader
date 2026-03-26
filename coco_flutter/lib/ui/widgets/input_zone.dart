/// InputZone — link input area with single/bulk mode toggle and drag-and-drop.
///
/// Features:
///   - Single-line [TextField] for one URL at a time (default mode).
///   - Multi-line [TextField] for bulk paste (one URL per line).
///   - Toggle button to switch between modes.
///   - 600 ms debounce timer that triggers [previewProvider.fetchPreview] after
///     the user stops typing.
///   - [DropTarget] wrapper (desktop_drop) to accept dragged URLs or .torrent
///     files.
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preview_provider.dart';

// ---------------------------------------------------------------------------
// InputZone
// ---------------------------------------------------------------------------

class InputZone extends ConsumerStatefulWidget {
  const InputZone({super.key});

  @override
  ConsumerState<InputZone> createState() => _InputZoneState();
}

class _InputZoneState extends ConsumerState<InputZone> {
  bool _bulkMode = false;
  bool _isDragging = false;

  final _singleController = TextEditingController();
  final _bulkController = TextEditingController();

  Timer? _debounce;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _debounce?.cancel();
    _singleController.dispose();
    _bulkController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Preview debounce
  // -------------------------------------------------------------------------

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _doPreview);
  }

  void _doPreview() {
    final text = _bulkMode
        ? _bulkController.text
        : _singleController.text;

    final links = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    ref.read(previewProvider.notifier).fetchPreview(links);
  }

  // -------------------------------------------------------------------------
  // Drag and drop
  // -------------------------------------------------------------------------

  void _handleDrop(DropDoneDetails details) {
    final lines = <String>[];

    for (final file in details.files) {
      final path = file.path;
      if (path.toLowerCase().endsWith('.torrent')) {
        lines.add(path);
      } else {
        lines.add(path);
      }
    }

    // Also try treating the text as a URL.
    if (lines.isEmpty) return;

    final joined = lines.join('\n');

    setState(() {
      _isDragging = false;
      _bulkMode = true;
      final current = _bulkController.text.trim();
      _bulkController.text =
          current.isEmpty ? joined : '$current\n$joined';
    });

    _schedulePreview();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: _handleDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isDragging
              ? cs.primaryContainer.withAlpha(80)
              : Colors.transparent,
          border: _isDragging
              ? Border.all(color: cs.primary, width: 2)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -----------------------------------------------------------------
            // Mode header row
            // -----------------------------------------------------------------
            Row(
              children: [
                Icon(
                  _isDragging ? Icons.file_download : Icons.link,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _isDragging
                      ? 'Drop links or .torrent files here'
                      : (_bulkMode ? 'Bulk Links' : 'Link'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                // Toggle bulk mode
                TextButton.icon(
                  onPressed: () => setState(() => _bulkMode = !_bulkMode),
                  icon: Icon(
                    _bulkMode ? Icons.list : Icons.format_list_bulleted_add,
                    size: 16,
                  ),
                  label: Text(_bulkMode ? 'Single mode' : 'Bulk mode'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // -----------------------------------------------------------------
            // Input field
            // -----------------------------------------------------------------
            if (!_bulkMode)
              TextField(
                controller: _singleController,
                decoration: InputDecoration(
                  hintText: 'Paste a URL, magnet link, or torrent path…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _singleController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _singleController.clear();
                            _doPreview();
                          },
                        )
                      : null,
                ),
                onChanged: (_) => _schedulePreview(),
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _doPreview();
                },
              )
            else
              TextField(
                controller: _bulkController,
                decoration: const InputDecoration(
                  hintText: 'Paste one link per line…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 4,
                minLines: 3,
                onChanged: (_) => _schedulePreview(),
              ),
          ],
        ),
      ),
    );
  }
}
