/// Privacy & Power dialog — power-aware throttling, user-agent rotation,
/// and smart auto-tuning settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';

class PrivacyPowerDialog extends ConsumerStatefulWidget {
  const PrivacyPowerDialog({super.key});

  @override
  ConsumerState<PrivacyPowerDialog> createState() => _PrivacyPowerDialogState();
}

class _PrivacyPowerDialogState extends ConsumerState<PrivacyPowerDialog> {
  // Power-aware
  late bool _enablePowerAware;
  late TextEditingController _batteryLimitCtrl;
  late TextEditingController _batteryConcurrentCtrl;
  late TextEditingController _acConcurrentCtrl;

  // Privacy
  late bool _rotateUserAgent;
  late TextEditingController _userAgentsCtrl;

  // Auto-tune
  late bool _enableAutoTune;
  late TextEditingController _tuneMinKibCtrl;
  late TextEditingController _tuneMaxConnCtrl;
  late TextEditingController _tuneMinConnCtrl;
  late TextEditingController _tuneIntervalCtrl;
  late TextEditingController _tuneEmaAlphaCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);

    _enablePowerAware = cfg.enablePowerAware;
    _batteryLimitCtrl = TextEditingController(text: cfg.batteryLimitKib.toString());
    _batteryConcurrentCtrl = TextEditingController(text: cfg.batteryConcurrent.toString());
    _acConcurrentCtrl = TextEditingController(text: cfg.acConcurrent.toString());

    _rotateUserAgent = cfg.rotateUserAgent;
    _userAgentsCtrl = TextEditingController(text: cfg.userAgents.join('\n'));

    _enableAutoTune = cfg.enableAutoTune;
    _tuneMinKibCtrl = TextEditingController(text: cfg.tuneMinKib.toString());
    _tuneMaxConnCtrl = TextEditingController(text: cfg.tuneMaxConn.toString());
    _tuneMinConnCtrl = TextEditingController(text: cfg.tuneMinConn.toString());
    _tuneIntervalCtrl = TextEditingController(text: cfg.tuneIntervalSec.toString());
    _tuneEmaAlphaCtrl = TextEditingController(text: cfg.tuneEmaAlpha.toString());
  }

  @override
  void dispose() {
    _batteryLimitCtrl.dispose();
    _batteryConcurrentCtrl.dispose();
    _acConcurrentCtrl.dispose();
    _userAgentsCtrl.dispose();
    _tuneMinKibCtrl.dispose();
    _tuneMaxConnCtrl.dispose();
    _tuneMinConnCtrl.dispose();
    _tuneIntervalCtrl.dispose();
    _tuneEmaAlphaCtrl.dispose();
    super.dispose();
  }

  int _parseInt(String text, int fallback) {
    return int.tryParse(text.trim()) ?? fallback;
  }

  double _parseDouble(String text, double fallback) {
    return double.tryParse(text.trim()) ?? fallback;
  }

  Future<void> _save() async {
    final agents = _userAgentsCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            enablePowerAware: _enablePowerAware,
            batteryLimitKib: _parseInt(_batteryLimitCtrl.text, 5120),
            batteryConcurrent: _parseInt(_batteryConcurrentCtrl.text, 2),
            acConcurrent: _parseInt(_acConcurrentCtrl.text, 1),
            rotateUserAgent: _rotateUserAgent,
            userAgents: agents,
            enableAutoTune: _enableAutoTune,
            tuneMinKib: _parseInt(_tuneMinKibCtrl.text, 64),
            tuneMaxConn: _parseInt(_tuneMaxConnCtrl.text, 16),
            tuneMinConn: _parseInt(_tuneMinConnCtrl.text, 1),
            tuneIntervalSec: _parseInt(_tuneIntervalCtrl.text, 20),
            tuneEmaAlpha: _parseDouble(_tuneEmaAlphaCtrl.text, 0.3),
          ),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privacy & Power'),
      content: SizedBox(
        width: 500,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Power-Aware Throttling'),
              SwitchListTile(
                title: const Text('Enable power-aware throttling (battery mode)'),
                value: _enablePowerAware,
                onChanged: (v) => setState(() => _enablePowerAware = v),
                contentPadding: EdgeInsets.zero,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _numField(_batteryLimitCtrl, 'Battery limit (KiB/s)'),
                  _numField(_batteryConcurrentCtrl, 'Battery concurrent'),
                  _numField(_acConcurrentCtrl, 'AC concurrent'),
                ],
              ),
              _sectionHeader('Privacy / User-Agent'),
              SwitchListTile(
                title: const Text('Rotate User-Agent for direct downloads'),
                value: _rotateUserAgent,
                onChanged: (v) => setState(() => _rotateUserAgent = v),
                contentPadding: EdgeInsets.zero,
              ),
              const Text('User-Agents (one per line):'),
              const SizedBox(height: 4),
              TextField(
                controller: _userAgentsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Mozilla/5.0 ...',
                ),
              ),
              _sectionHeader('Smart Auto-Tuning'),
              SwitchListTile(
                title: const Text('Enable smart auto-tuning (per-task connections)'),
                value: _enableAutoTune,
                onChanged: (v) => setState(() => _enableAutoTune = v),
                contentPadding: EdgeInsets.zero,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _numField(_tuneMinKibCtrl, 'Min speed (KiB/s)'),
                  _numField(_tuneMaxConnCtrl, 'Max conn'),
                  _numField(_tuneMinConnCtrl, 'Min conn'),
                  _numField(_tuneIntervalCtrl, 'Interval (s)'),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _tuneEmaAlphaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'EMA alpha',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
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

/// Convenience helper to show [PrivacyPowerDialog].
Future<bool?> showPrivacyPowerDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const PrivacyPowerDialog(),
  );
}
