/// Settings screen — tabbed settings consolidating all configuration areas.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../dialogs/oauth_dialog.dart';
import '../dialogs/token_dialog.dart';

// ---------------------------------------------------------------------------
// SettingsScreen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Account'),
            Tab(text: 'Network'),
            Tab(text: 'File Rules'),
            Tab(text: 'Scheduler'),
            Tab(text: 'Advanced'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _GeneralTab(),
          _AccountTab(),
          _NetworkTab(),
          _FileRulesTab(),
          _SchedulerTab(),
          _AdvancedTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// General tab
// ---------------------------------------------------------------------------

class _GeneralTab extends ConsumerStatefulWidget {
  const _GeneralTab();

  @override
  ConsumerState<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends ConsumerState<_GeneralTab> {
  late TextEditingController _outdirCtrl;
  late TextEditingController _connCtrl;
  late TextEditingController _splitsCtrl;
  late TextEditingController _concurrencyCtrl;
  late bool _darkMode;
  late bool _openOnDone;
  late bool _autoStartRd;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _outdirCtrl = TextEditingController(text: cfg.outdir);
    _connCtrl = TextEditingController(text: cfg.connections.toString());
    _splitsCtrl = TextEditingController(text: cfg.splits.toString());
    _concurrencyCtrl = TextEditingController(text: cfg.concurrency.toString());
    _darkMode = cfg.darkMode;
    _openOnDone = cfg.openOnDone;
    _autoStartRd = cfg.autoStartRdOnAdd;
  }

  @override
  void dispose() {
    _outdirCtrl.dispose();
    _connCtrl.dispose();
    _splitsCtrl.dispose();
    _concurrencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose download directory',
    );
    if (result != null) {
      setState(() {
        _outdirCtrl.text = result;
      });
    }
  }

  Future<void> _save() async {
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            outdir: _outdirCtrl.text.trim(),
            connections: int.tryParse(_connCtrl.text) ?? c.connections,
            splits: int.tryParse(_splitsCtrl.text) ?? c.splits,
            concurrency: int.tryParse(_concurrencyCtrl.text) ?? c.concurrency,
            darkMode: _darkMode,
            openOnDone: _openOnDone,
            autoStartRdOnAdd: _autoStartRd,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('General settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsForm(
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Download Directory'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _outdirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Output directory',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickDir,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('aria2 Parameters'),
          Row(
            children: [
              _IntField(
                ctrl: _connCtrl,
                label: 'Connections (-x)',
              ),
              const SizedBox(width: 12),
              _IntField(
                ctrl: _splitsCtrl,
                label: 'Splits (-s)',
              ),
              const SizedBox(width: 12),
              _IntField(
                ctrl: _concurrencyCtrl,
                label: 'Concurrency (-j)',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('UI Options'),
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (v) => setState(() => _darkMode = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Open download folder when done'),
            value: _openOnDone,
            onChanged: (v) => setState(() => _openOnDone = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Auto-start Real-Debrid unrestrict after adding'),
            value: _autoStartRd,
            onChanged: (v) => setState(() => _autoStartRd = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account tab
// ---------------------------------------------------------------------------

class _AccountTab extends ConsumerWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return _SettingsForm(
      showSave: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Real-Debrid API Token'),
          Row(
            children: [
              Icon(
                authState.isAuthenticated ? Icons.check_circle : Icons.cancel,
                color: authState.isAuthenticated ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(authState.isAuthenticated
                  ? 'Token set (${_masked(authState.token)})'
                  : 'No token configured'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => showTokenDialog(context),
                icon: const Icon(Icons.key),
                label: const Text('Set API Token'),
              ),
              if (authState.isAuthenticated)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(authProvider.notifier).clearToken(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Clear Token'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle('OAuth Device Flow'),
          const Text(
            'Use the OAuth device-code flow if you prefer not to paste a raw token. '
            'You will be shown a short code to enter on the Real-Debrid website.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showOAuthDialog(context),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Authenticate via OAuth'),
          ),
        ],
      ),
    );
  }

  static String _masked(String? token) {
    if (token == null || token.length < 8) return '****';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }
}

// ---------------------------------------------------------------------------
// Network tab
// ---------------------------------------------------------------------------

class _NetworkTab extends ConsumerStatefulWidget {
  const _NetworkTab();

  @override
  ConsumerState<_NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends ConsumerState<_NetworkTab> {
  late TextEditingController _httpProxyCtrl;
  late TextEditingController _httpsProxyCtrl;
  late TextEditingController _headersCtrl;

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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsForm(
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Proxy'),
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
          const SizedBox(height: 20),
          _SectionTitle('Custom Headers'),
          const Text('One header per line in "Key: Value" format:'),
          const SizedBox(height: 4),
          TextField(
            controller: _headersCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Authorization: Bearer token\nX-Custom: value',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File Rules tab
// ---------------------------------------------------------------------------

const _defaultCategories = [
  'Video',
  'Audio',
  'Images',
  'Documents',
  'Archives',
  'Software',
];

class _FileRulesTab extends ConsumerStatefulWidget {
  const _FileRulesTab();

  @override
  ConsumerState<_FileRulesTab> createState() => _FileRulesTabState();
}

class _FileRulesTabState extends ConsumerState<_FileRulesTab>
    with SingleTickerProviderStateMixin {
  late TabController _inner;
  late TextEditingController _excludeCtrl;
  late bool _autoCategorize;
  late Map<String, TextEditingController> _extCtrls;
  late Map<String, TextEditingController> _folderCtrls;

  @override
  void initState() {
    super.initState();
    _inner = TabController(length: 3, vsync: this);
    final cfg = ref.read(configProvider);
    _autoCategorize = cfg.autoCategorize;
    _excludeCtrl = TextEditingController(text: cfg.excludeExt.join(', '));
    final cats = cfg.categoryExts.keys.toSet()..addAll(_defaultCategories);
    _extCtrls = {
      for (final cat in cats)
        cat: TextEditingController(
          text: (cfg.categoryExts[cat] ?? []).join(', '),
        ),
    };
    _folderCtrls = {
      for (final cat in cats)
        cat: TextEditingController(text: cfg.categoryFolders[cat] ?? cat),
    };
  }

  @override
  void dispose() {
    _inner.dispose();
    _excludeCtrl.dispose();
    for (final c in _extCtrls.values) {
      c.dispose();
    }
    for (final c in _folderCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _parseCommaList(String text) {
    return text
        .split(',')
        .map((s) => s.trim().toLowerCase().replaceAll('.', ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final categoryExts = <String, List<String>>{
      for (final e in _extCtrls.entries) e.key: _parseCommaList(e.value.text),
    };
    final categoryFolders = <String, String>{
      for (final e in _folderCtrls.entries)
        e.key: e.value.text.trim().isNotEmpty ? e.value.text.trim() : e.key,
    };
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            autoCategorize: _autoCategorize,
            excludeExt: _parseCommaList(_excludeCtrl.text),
            categoryExts: categoryExts,
            categoryFolders: categoryFolders,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File rules saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _inner,
          tabs: const [
            Tab(text: 'Exclusions'),
            Tab(text: 'Category Exts'),
            Tab(text: 'Folders'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _inner,
            children: [
              _SettingsForm(
                onSave: _save,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Extensions to exclude from downloads (comma-separated, no dot):',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _excludeCtrl,
                      decoration: const InputDecoration(
                        hintText: 'nfo, jpg, txt',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Auto-categorize downloads'),
                      value: _autoCategorize,
                      onChanged: (v) => setState(() => _autoCategorize = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              _SettingsForm(
                onSave: _save,
                child: ListView.separated(
                  itemCount: _extCtrls.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final cat = _extCtrls.keys.elementAt(i);
                    return TextField(
                      controller: _extCtrls[cat],
                      decoration: InputDecoration(
                        labelText: cat,
                        hintText: 'mkv, mp4, avi',
                        border: const OutlineInputBorder(),
                      ),
                    );
                  },
                ),
              ),
              _SettingsForm(
                onSave: _save,
                child: ListView.separated(
                  itemCount: _folderCtrls.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final cat = _folderCtrls.keys.elementAt(i);
                    return TextField(
                      controller: _folderCtrls[cat],
                      decoration: InputDecoration(
                        labelText: '$cat folder name',
                        hintText: cat,
                        border: const OutlineInputBorder(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scheduler tab
// ---------------------------------------------------------------------------

class _SchedulerTab extends ConsumerStatefulWidget {
  const _SchedulerTab();

  @override
  ConsumerState<_SchedulerTab> createState() => _SchedulerTabState();
}

class _SchedulerTabState extends ConsumerState<_SchedulerTab> {
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
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

  Future<void> _save() async {
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            quietStart: _startCtrl.text.trim(),
            quietEnd: _endCtrl.text.trim(),
            autoExtractZip: _autoExtract,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scheduler settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsForm(
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Quiet Hours'),
          const Text(
            'Downloads will be paused during the quiet window. '
            'Leave empty to disable.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Start (HH:MM)',
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
                    labelText: 'End (HH:MM)',
                    hintText: '07:00',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('Post-Download'),
          SwitchListTile(
            title: const Text('Auto-extract ZIP files after download'),
            value: _autoExtract,
            onChanged: (v) => setState(() => _autoExtract = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced tab
// ---------------------------------------------------------------------------

class _AdvancedTab extends ConsumerStatefulWidget {
  const _AdvancedTab();

  @override
  ConsumerState<_AdvancedTab> createState() => _AdvancedTabState();
}

class _AdvancedTabState extends ConsumerState<_AdvancedTab> {
  // Power-aware
  late bool _enablePowerAware;
  late TextEditingController _batteryLimitCtrl;
  late TextEditingController _batteryConcCtrl;
  late TextEditingController _acConcCtrl;

  // Privacy
  late bool _rotateUA;
  late TextEditingController _userAgentsCtrl;

  // Auto-tune
  late bool _enableAutoTune;
  late TextEditingController _tuneMinKibCtrl;
  late TextEditingController _tuneMaxConnCtrl;
  late TextEditingController _tuneMinConnCtrl;
  late TextEditingController _tuneIntervalCtrl;
  late TextEditingController _tuneEmaAlphaCtrl;

  // Dedup / encryption
  late bool _dedup;
  late bool _autoRename;
  late bool _encrypt;

  // aria2 path
  late TextEditingController _aria2PathCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _enablePowerAware = cfg.enablePowerAware;
    _batteryLimitCtrl = TextEditingController(text: cfg.batteryLimitKib.toString());
    _batteryConcCtrl = TextEditingController(text: cfg.batteryConcurrent.toString());
    _acConcCtrl = TextEditingController(text: cfg.acConcurrent.toString());
    _rotateUA = cfg.rotateUserAgent;
    _userAgentsCtrl = TextEditingController(text: cfg.userAgents.join('\n'));
    _enableAutoTune = cfg.enableAutoTune;
    _tuneMinKibCtrl = TextEditingController(text: cfg.tuneMinKib.toString());
    _tuneMaxConnCtrl = TextEditingController(text: cfg.tuneMaxConn.toString());
    _tuneMinConnCtrl = TextEditingController(text: cfg.tuneMinConn.toString());
    _tuneIntervalCtrl = TextEditingController(text: cfg.tuneIntervalSec.toString());
    _tuneEmaAlphaCtrl = TextEditingController(text: cfg.tuneEmaAlpha.toString());
    _dedup = cfg.dedupOnComplete;
    _autoRename = cfg.autoRenameMedia;
    _encrypt = cfg.encryptCompleted;
    _aria2PathCtrl = TextEditingController(text: cfg.aria2Path ?? '');
  }

  @override
  void dispose() {
    _batteryLimitCtrl.dispose();
    _batteryConcCtrl.dispose();
    _acConcCtrl.dispose();
    _userAgentsCtrl.dispose();
    _tuneMinKibCtrl.dispose();
    _tuneMaxConnCtrl.dispose();
    _tuneMinConnCtrl.dispose();
    _tuneIntervalCtrl.dispose();
    _tuneEmaAlphaCtrl.dispose();
    _aria2PathCtrl.dispose();
    super.dispose();
  }

  int _parseInt(String t, int fb) => int.tryParse(t.trim()) ?? fb;
  double _parseDouble(String t, double fb) => double.tryParse(t.trim()) ?? fb;

  Future<void> _save() async {
    final agents = _userAgentsCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final aria2Path = _aria2PathCtrl.text.trim();
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            enablePowerAware: _enablePowerAware,
            batteryLimitKib: _parseInt(_batteryLimitCtrl.text, 5120),
            batteryConcurrent: _parseInt(_batteryConcCtrl.text, 2),
            acConcurrent: _parseInt(_acConcCtrl.text, 1),
            rotateUserAgent: _rotateUA,
            userAgents: agents,
            enableAutoTune: _enableAutoTune,
            tuneMinKib: _parseInt(_tuneMinKibCtrl.text, 64),
            tuneMaxConn: _parseInt(_tuneMaxConnCtrl.text, 16),
            tuneMinConn: _parseInt(_tuneMinConnCtrl.text, 1),
            tuneIntervalSec: _parseInt(_tuneIntervalCtrl.text, 20),
            tuneEmaAlpha: _parseDouble(_tuneEmaAlphaCtrl.text, 0.3),
            dedupOnComplete: _dedup,
            autoRenameMedia: _autoRename,
            encryptCompleted: _encrypt,
            aria2Path: aria2Path.isEmpty ? null : aria2Path,
            clearAria2Path: aria2Path.isEmpty,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Advanced settings saved')),
      );
    }
  }

  Widget _numField(TextEditingController ctrl, String label,
      {bool decimal = false}) {
    return SizedBox(
      width: 130,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        inputFormatters: decimal
            ? []
            : [FilteringTextInputFormatter.digitsOnly],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsForm(
      onSave: _save,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Power-Aware Throttling'),
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
                _numField(_batteryConcCtrl, 'Battery concurrent'),
                _numField(_acConcCtrl, 'AC concurrent'),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Privacy / User-Agent'),
            SwitchListTile(
              title: const Text('Rotate User-Agent for direct downloads'),
              value: _rotateUA,
              onChanged: (v) => setState(() => _rotateUA = v),
              contentPadding: EdgeInsets.zero,
            ),
            const Text('User-Agents (one per line):'),
            const SizedBox(height: 4),
            TextField(
              controller: _userAgentsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Mozilla/5.0 ...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Smart Auto-Tuning'),
            SwitchListTile(
              title: const Text(
                  'Enable smart auto-tuning (per-task connections)'),
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
                _numField(_tuneEmaAlphaCtrl, 'EMA alpha', decimal: true),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Dedup & Encryption'),
            SwitchListTile(
              title: const Text('Check for duplicates by hash after download'),
              value: _dedup,
              onChanged: (v) => setState(() => _dedup = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Auto-rename media files'),
              value: _autoRename,
              onChanged: (v) => setState(() => _autoRename = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Encrypt completed downloads'),
              value: _encrypt,
              onChanged: (v) => setState(() => _encrypt = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 20),
            _SectionTitle('aria2 Path'),
            TextField(
              controller: _aria2PathCtrl,
              decoration: const InputDecoration(
                labelText: 'Path to aria2c (leave blank for PATH lookup)',
                hintText: '/usr/bin/aria2c',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SettingsForm extends StatelessWidget {
  const _SettingsForm({
    required this.child,
    this.onSave,
    this.showSave = true,
  });

  final Widget child;
  final VoidCallback? onSave;
  final bool showSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(child: child),
          ),
          if (showSave) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onSave,
                child: const Text('Save'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({
    required this.ctrl,
    required this.label,
  });

  final TextEditingController ctrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
  }
}
