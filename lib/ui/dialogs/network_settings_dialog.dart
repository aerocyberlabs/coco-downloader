/// Network settings dialog — HTTP/HTTPS proxy and custom headers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';

class NetworkSettingsDialog extends ConsumerStatefulWidget {
  const NetworkSettingsDialog({super.key});

  @override
  ConsumerState<NetworkSettingsDialog> createState() =>
      _NetworkSettingsDialogState();
}

class _NetworkSettingsDialogState
    extends ConsumerState<NetworkSettingsDialog> {
  late final TextEditingController _httpProxyCtrl;
  late final TextEditingController _httpsProxyCtrl;
  late final TextEditingController _headersCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _httpProxyCtrl = TextEditingController(text: cfg.httpProxy);
    _httpsProxyCtrl = TextEditingController(text: cfg.httpsProxy);
    _headersCtrl = TextEditingController(text: cfg.headers.join('\n'));
  }

  @override
  void dispose() {
    _httpProxyCtrl.dispose();
    _httpsProxyCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lines = _headersCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            httpProxy: _httpProxyCtrl.text.trim(),
            httpsProxy: _httpsProxyCtrl.text.trim(),
            headers: lines,
          ),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Network Settings'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _httpProxyCtrl,
                decoration: const InputDecoration(
                  labelText: 'HTTP proxy',
                  hintText: 'http://user:pass@host:port',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _httpsProxyCtrl,
                decoration: const InputDecoration(
                  labelText: 'HTTPS proxy',
                  hintText: 'http://user:pass@host:port',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Extra HTTP headers (one per line: Key: Value)'),
              const SizedBox(height: 4),
              TextField(
                controller: _headersCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Authorization: Bearer token\nX-Custom: value',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
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

/// Convenience helper to show [NetworkSettingsDialog].
Future<bool?> showNetworkSettingsDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const NetworkSettingsDialog(),
  );
}
