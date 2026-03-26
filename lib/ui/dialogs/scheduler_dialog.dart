/// Scheduler dialog — quiet hours and auto-extract settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';

class SchedulerDialog extends ConsumerStatefulWidget {
  const SchedulerDialog({super.key});

  @override
  ConsumerState<SchedulerDialog> createState() => _SchedulerDialogState();
}

class _SchedulerDialogState extends ConsumerState<SchedulerDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late bool _autoExtract;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _startCtrl = TextEditingController(text: cfg.quietStart);
    _endCtrl = TextEditingController(text: cfg.quietEnd);
    _autoExtract = cfg.autoExtractZip;
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  bool _validTime(String s) {
    if (s.isEmpty) return true;
    final re = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    return re.hasMatch(s);
  }

  Future<void> _save() async {
    if (!_validTime(_startCtrl.text) || !_validTime(_endCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Times must be in HH:MM format')),
      );
      return;
    }
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            quietStart: _startCtrl.text.trim(),
            quietEnd: _endCtrl.text.trim(),
            autoExtractZip: _autoExtract,
          ),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scheduler'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quiet start (HH:MM)',
                      hintText: '23:00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quiet end (HH:MM)',
                      hintText: '07:00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Auto-extract ZIP after download'),
              value: _autoExtract,
              onChanged: (v) => setState(() => _autoExtract = v),
              contentPadding: EdgeInsets.zero,
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

/// Convenience helper to show [SchedulerDialog].
Future<bool?> showSchedulerDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const SchedulerDialog(),
  );
}
