/// About dialog — app info, version, and support link.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';

class AppAboutDialog extends StatelessWidget {
  const AppAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('About'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_rounded, size: 64),
            const SizedBox(height: 12),
            Text(
              appName,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Version $version',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            const Text(
              'Cross-platform download manager with Real-Debrid integration, '
              'powered by aria2.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(supportUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('GitHub / Support'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Convenience helper to show [AppAboutDialog].
Future<void> showAppAboutDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const AppAboutDialog(),
  );
}
