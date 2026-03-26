/// Add page dialog — scrape a web page for downloadable links.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

const _assetExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg',
  '.mp4', '.webm', '.mkv', '.avi', '.mov',
  '.mp3', '.flac', '.ogg', '.wav', '.m4a',
  '.zip', '.rar', '.7z', '.tar', '.gz',
  '.pdf', '.epub',
};

class AddPageDialog extends StatefulWidget {
  const AddPageDialog({super.key});

  @override
  State<AddPageDialog> createState() => _AddPageDialogState();
}

class _AddPageDialogState extends State<AddPageDialog> {
  final _urlCtrl = TextEditingController();
  bool _scraping = false;
  String? _error;
  List<String> _foundLinks = [];
  final Set<int> _selected = {};

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _scrape() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _scraping = true;
      _error = null;
      _foundLinks = [];
      _selected.clear();
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final resp = await dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final doc = html_parser.parse(resp.data ?? '');
      final baseUri = Uri.tryParse(url);
      final links = <String>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final lower = href.toLowerCase();
        if (!_assetExtensions.any((ext) => lower.endsWith(ext))) continue;
        // Resolve relative URLs.
        final resolved = baseUri != null ? baseUri.resolve(href).toString() : href;
        if (!links.contains(resolved)) links.add(resolved);
      }

      setState(() {
        _foundLinks = links;
        _selected.addAll(Iterable.generate(links.length));
        _scraping = false;
        if (links.isEmpty) _error = 'No downloadable links found on that page.';
      });
    } catch (e) {
      setState(() {
        _scraping = false;
        _error = 'Failed to fetch page: $e';
      });
    }
  }

  void _addSelected() {
    final selected = [
      for (int i = 0; i < _foundLinks.length; i++)
        if (_selected.contains(i)) _foundLinks[i],
    ];
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add from Page'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Page URL',
                      hintText: 'https://example.com/downloads',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _scrape(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _scraping ? null : _scrape,
                  child: _scraping
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Scrape'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_foundLinks.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Found ${_foundLinks.length} link(s):'),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selected.length == _foundLinks.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(
                              Iterable.generate(_foundLinks.length));
                        }
                      });
                    },
                    child: Text(
                      _selected.length == _foundLinks.length
                          ? 'Deselect all'
                          : 'Select all',
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _foundLinks.length,
                  itemBuilder: (_, i) {
                    return CheckboxListTile(
                      value: _selected.contains(i),
                      title: Text(
                        _foundLinks[i],
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(i);
                          } else {
                            _selected.remove(i);
                          }
                        });
                      },
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
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
          onPressed: _selected.isNotEmpty ? _addSelected : null,
          child: Text('Add ${_selected.isEmpty ? '' : '(${_selected.length})'}'),
        ),
      ],
    );
  }
}

/// Shows [AddPageDialog] and returns the selected list of URLs, or null.
Future<List<String>?> showAddPageDialog(BuildContext context) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => const AddPageDialog(),
  );
}
