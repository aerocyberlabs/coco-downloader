/// OAuth dialog — Real-Debrid device-code flow.
///
/// Shows the user_code that the user must type at the RD website, provides
/// a "Copy code" button and an "Open RD" button, and polls for credentials
/// in the background. Auto-closes on success.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/real_debrid/rd_oauth.dart';

class OAuthDialog extends ConsumerStatefulWidget {
  const OAuthDialog({super.key});

  @override
  ConsumerState<OAuthDialog> createState() => _OAuthDialogState();
}

class _OAuthDialogState extends ConsumerState<OAuthDialog> {
  String? _userCode;
  String? _verificationUrl;
  String? _deviceCode;
  bool _loading = true;
  bool _polling = false;
  String? _error;
  Timer? _pollTimer;
  int _countdown = 120;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _startFlow() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await deviceCode();
      _deviceCode = data['device_code'] as String?;
      final interval = (data['interval'] as num?)?.toInt() ?? 5;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 120;
      setState(() {
        _userCode = data['user_code'] as String?;
        _verificationUrl =
            data['verification_url'] as String? ?? 'https://real-debrid.com/device';
        _loading = false;
        _polling = true;
        _countdown = expiresIn;
      });
      _startCountdown();
      ref.read(authProvider.notifier).startOAuth();
      _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => _poll());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to start OAuth: $e';
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) _countdown--;
      });
    });
  }

  Future<void> _poll() async {
    if (_deviceCode == null) return;
    try {
      final creds = await pollCredentials(_deviceCode!, timeout: 10);
      final clientId = creds['client_id'] as String?;
      final clientSecret = creds['client_secret'] as String?;
      if (clientId == null || clientSecret == null) return;

      // Exchange for tokens.
      final tokens = await exchangeToken(clientId, clientSecret, _deviceCode!);
      final accessToken = tokens['access_token'] as String?;
      final refreshToken = tokens['refresh_token'] as String?;
      if (accessToken == null) return;

      _pollTimer?.cancel();
      _countdownTimer?.cancel();

      await ref.read(authProvider.notifier).completeOAuth(
            OAuthCredentials(
              clientId: clientId,
              clientSecret: clientSecret,
              accessToken: accessToken,
              refreshToken: refreshToken ?? '',
            ),
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // Still waiting — ignore until timeout or success.
    }
  }

  Future<void> _copyCode() async {
    if (_userCode == null) return;
    await Clipboard.setData(ClipboardData(text: _userCode!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code copied to clipboard')),
      );
    }
  }

  Future<void> _openRd() async {
    final url = Uri.tryParse(_verificationUrl ?? 'https://real-debrid.com/device');
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _cancel() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    ref.read(authProvider.notifier).cancelOAuth();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visit the Real-Debrid device page and enter the code below:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _userCode ?? '',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy),
                label: const Text('Copy code'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openRd,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open RD'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_polling) ...[
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Waiting for authorisation... ($_countdown s remaining)'),
              ],
            ),
          ],
        ],
      );
    }

    return AlertDialog(
      title: const Text('Real-Debrid OAuth'),
      content: SizedBox(width: 400, child: body),
      actions: [
        TextButton(
          onPressed: _error != null ? _startFlow : _cancel,
          child: Text(_error != null ? 'Retry' : 'Cancel'),
        ),
      ],
    );
  }
}

/// Convenience helper to show [OAuthDialog] as a modal dialog.
Future<bool?> showOAuthDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const OAuthDialog(),
  );
}
