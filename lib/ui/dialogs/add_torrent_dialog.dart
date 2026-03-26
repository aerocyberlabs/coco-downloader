/// Add torrent dialog — pick a .torrent file.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class AddTorrentDialog extends StatefulWidget {
  const AddTorrentDialog({super.key});

  @override
  State<AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends State<AddTorrentDialog> {
  String? _selectedPath;
  String? _selectedName;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
      dialogTitle: 'Select .torrent file',
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _selectedPath = file.path;
        _selectedName = file.name;
      });
    }
  }

  void _add() {
    if (_selectedPath == null) return;
    Navigator.of(context).pop(_selectedPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add Torrent'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a .torrent file to add via Real-Debrid.'),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse...'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedName ?? 'No file selected',
                    style: _selectedName == null
                        ? theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)
                        : theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedPath != null ? _add : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Shows [AddTorrentDialog] and returns the selected file path, or null.
Future<String?> showAddTorrentDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const AddTorrentDialog(),
  );
}
