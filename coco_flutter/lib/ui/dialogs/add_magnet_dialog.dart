/// Add magnet dialog — paste a magnet URI.
library;

import 'package:flutter/material.dart';

class AddMagnetDialog extends StatefulWidget {
  const AddMagnetDialog({super.key});

  @override
  State<AddMagnetDialog> createState() => _AddMagnetDialogState();
}

class _AddMagnetDialogState extends State<AddMagnetDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final magnet = _controller.text.trim();
    if (magnet.isEmpty) return;
    Navigator.of(context).pop(magnet);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Magnet'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste a magnet URI to add via Real-Debrid.'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Magnet URI',
                hintText: 'magnet:?xt=urn:btih:...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              maxLines: 3,
              onSubmitted: (_) => _add(),
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
          onPressed: _add,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Shows [AddMagnetDialog] and returns the magnet URI, or null.
Future<String?> showAddMagnetDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const AddMagnetDialog(),
  );
}
