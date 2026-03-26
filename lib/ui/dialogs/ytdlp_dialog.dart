/// yt-dlp dialog — resolve a media URL via the yt-dlp CLI tool.
///
/// Calls `yt-dlp --get-url` as a subprocess and shows the resolved direct URL.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class YtDlpDialog extends StatefulWidget {
  const YtDlpDialog({super.key});

  @override
  State<YtDlpDialog> createState() => _YtDlpDialogState();
}

class _YtDlpDialogState extends State<YtDlpDialog> {
  final _urlCtrl = TextEditingController();
  bool _resolving = false;
  String? _resolvedUrl;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _resolving = true;
      _resolvedUrl = null;
      _error = null;
    });

    try {
      final result = await Process.run(
        'yt-dlp',
        ['--get-url', '--no-playlist', url],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        // yt-dlp may return multiple lines; take the first non-empty one.
        final lines = out.split('\n').where((l) => l.trim().isNotEmpty).toList();
        setState(() {
          _resolvedUrl = lines.isNotEmpty ? lines.first : null;
          _resolving = false;
          if (_resolvedUrl == null) _error = 'yt-dlp returned no URL.';
        });
      } else {
        final err = (result.stderr as String).trim();
        setState(() {
          _resolving = false;
          _error = err.isNotEmpty ? err : 'yt-dlp exited with code ${result.exitCode}';
        });
      }
    } on ProcessException catch (e) {
      setState(() {
        _resolving = false;
        _error = 'yt-dlp not found or not installed: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _resolving = false;
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _copyResolved() async {
    if (_resolvedUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _resolvedUrl!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL copied to clipboard')),
      );
    }
  }

  void _add() {
    if (_resolvedUrl == null) return;
    Navigator.of(context).pop(_resolvedUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add via yt-dlp'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a media page URL. yt-dlp will extract the direct download link.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Media page URL',
                      hintText: 'https://www.youtube.com/watch?v=...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _resolve(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _resolving ? null : _resolve,
                  child: _resolving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resolve'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_resolvedUrl != null) ...[
              const SizedBox(height: 12),
              const Text('Resolved URL:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _resolvedUrl!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy URL',
                      onPressed: _copyResolved,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _resolvedUrl != null ? _add : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Shows [YtDlpDialog] and returns the resolved direct URL, or null.
Future<String?> showYtDlpDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const YtDlpDialog(),
  );
}
