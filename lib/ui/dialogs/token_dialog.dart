/// Token dialog — enter and optionally save a Real-Debrid API token.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

class TokenDialog extends ConsumerStatefulWidget {
  const TokenDialog({super.key});

  @override
  ConsumerState<TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends ConsumerState<TokenDialog> {
  final _controller = TextEditingController();
  bool _obscured = true;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(authProvider).token;
    if (existing != null) _controller.text = existing;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    ref.read(authProvider.notifier).setToken(token, remember: _remember);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Set API Token'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your Real-Debrid API token. You can find it at '
              'real-debrid.com/apitoken.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              obscureText: _obscured,
              decoration: InputDecoration(
                labelText: 'API Token',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscured ? 'Show token' : 'Hide token',
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                ),
                const SizedBox(width: 4),
                const Text('Remember token'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Convenience helper to show [TokenDialog] as a modal dialog.
Future<bool?> showTokenDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const TokenDialog(),
  );
}
