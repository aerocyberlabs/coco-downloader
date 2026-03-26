/// File types dialog — excluded extensions, category extensions, category folders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';

// Default categories matching the Python app.
const _defaultCategories = ['Video', 'Audio', 'Images', 'Documents', 'Archives', 'Software'];

class FileTypesDialog extends ConsumerStatefulWidget {
  const FileTypesDialog({super.key});

  @override
  ConsumerState<FileTypesDialog> createState() => _FileTypesDialogState();
}

class _FileTypesDialogState extends ConsumerState<FileTypesDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _excludeCtrl;
  late bool _autoCategorize;

  // Per-category controllers for extensions and folder names.
  late Map<String, TextEditingController> _extCtrls;
  late Map<String, TextEditingController> _folderCtrls;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _tabController.dispose();
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
    final excludeExt = _parseCommaList(_excludeCtrl.text);
    final categoryExts = <String, List<String>>{
      for (final entry in _extCtrls.entries)
        entry.key: _parseCommaList(entry.value.text),
    };
    final categoryFolders = <String, String>{
      for (final entry in _folderCtrls.entries)
        entry.key: entry.value.text.trim().isNotEmpty
            ? entry.value.text.trim()
            : entry.key,
    };
    await ref.read(configProvider.notifier).updateConfig(
          (c) => c.copyWith(
            autoCategorize: _autoCategorize,
            excludeExt: excludeExt,
            categoryExts: categoryExts,
            categoryFolders: categoryFolders,
          ),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _buildExcludeTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Extensions to exclude from downloads (comma-separated):'),
          const SizedBox(height: 8),
          TextField(
            controller: _excludeCtrl,
            decoration: const InputDecoration(
              hintText: 'nfo, jpg, txt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Auto-categorize downloads'),
            value: _autoCategorize,
            onChanged: (v) => setState(() => _autoCategorize = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryExtsTab() {
    final cats = _extCtrls.keys.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: cats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final cat = cats[i];
        return TextField(
          controller: _extCtrls[cat],
          decoration: InputDecoration(
            labelText: cat,
            hintText: 'mkv, mp4, avi',
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }

  Widget _buildCategoryFoldersTab() {
    final cats = _folderCtrls.keys.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: cats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final cat = cats[i];
        return TextField(
          controller: _folderCtrls[cat],
          decoration: InputDecoration(
            labelText: '$cat folder name',
            hintText: cat,
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File Type Rules'),
      content: SizedBox(
        width: 460,
        height: 380,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Excluded'),
                Tab(text: 'Category Exts'),
                Tab(text: 'Folders'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExcludeTab(),
                  _buildCategoryExtsTab(),
                  _buildCategoryFoldersTab(),
                ],
              ),
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

/// Convenience helper to show [FileTypesDialog].
Future<bool?> showFileTypesDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const FileTypesDialog(),
  );
}
