/// Help dialog — tabbed reference documentation.
library;

import 'package:flutter/material.dart';

class HelpDialogWidget extends StatefulWidget {
  const HelpDialogWidget({super.key});

  @override
  State<HelpDialogWidget> createState() => _HelpDialogWidgetState();
}

class _HelpDialogWidgetState extends State<HelpDialogWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _richText(List<_HelpSection> sections) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in sections) ...[
            if (section.title != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  section.title!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            for (final item in section.items)
              Padding(
                padding: EdgeInsets.only(
                  left: section.ordered || section.bulleted ? 0 : 0,
                  bottom: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (section.bulleted)
                      const Text('  \u2022  ', style: TextStyle(fontSize: 13))
                    else if (section.ordered)
                      Text(
                        '  ${section.items.indexOf(item) + 1}.  ',
                        style: const TextStyle(fontSize: 13),
                      )
                    else
                      const SizedBox.shrink(),
                    Expanded(child: item),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _overviewTab() {
    return _richText([
      _HelpSection(
        title: 'Coco Downloader',
        items: [
          const Text(
            'Cross-platform GUI downloader powered by aria2 and optional Real-Debrid integration.',
          ),
        ],
      ),
      _HelpSection(
        bulleted: true,
        items: [
          const Text('Direct HTTP/HTTPS downloads (no token needed)'),
          const Text('Real-Debrid hosters, torrents, and magnets (API token required)'),
          const Text('Pause/Resume/Cancel, concurrent downloads, per-file progress'),
          const Text('Category-based folder organisation and file type filtering'),
        ],
      ),
    ]);
  }

  Widget _gettingStartedTab() {
    return _richText([
      _HelpSection(
        title: 'Direct Downloads',
        ordered: true,
        items: [
          const Text('Paste direct HTTP/HTTPS URLs into the input box'),
          const Text('Click Preview, select items, choose a folder'),
          const Text('Click Download'),
        ],
      ),
      _HelpSection(
        title: 'Real-Debrid',
        ordered: true,
        items: [
          const Text('Get your API token at real-debrid.com/apitoken'),
          const Text('Set token via Settings \u2192 Account \u2192 Set API Token'),
          const Text('Paste supported hoster links (or add torrent/magnet)'),
          const Text('Preview, then Download'),
        ],
      ),
    ]);
  }

  Widget _controlsTab() {
    return _richText([
      _HelpSection(
        bulleted: true,
        items: [
          const Text('Pause / Resume all downloads with the toolbar buttons'),
          const Text('Cancel stops and cleans up all running tasks'),
          const Text('Right-click a row for per-item Pause/Resume/Cancel/Open/Copy URL'),
          const Text('Active | Queued counters show current queue status'),
          const Text('Drag & drop files or URLs onto the input area'),
          const Text('Bulk mode allows multiple URLs to be pasted at once'),
        ],
      ),
    ]);
  }

  Widget _settingsTab() {
    return _richText([
      _HelpSection(
        bulleted: true,
        items: [
          const Text('Connections (-x): max connections per download'),
          const Text('Splits (-s): segments per file'),
          const Text('Concurrency (-j): concurrent downloads'),
          const Text('Dark mode and Open folder when done'),
          const Text('Network: HTTP/HTTPS proxy, custom headers'),
          const Text('Scheduler: quiet hours, auto-extract ZIP'),
          const Text('File Rules: excluded extensions, category mappings'),
          const Text('Advanced: power-aware throttling, user-agent rotation, auto-tune'),
        ],
      ),
    ]);
  }

  Widget _troubleshootingTab() {
    return _richText([
      _HelpSection(
        bulleted: true,
        items: [
          const Text(
            'If aria2 is missing, install it or configure its path in Advanced settings.',
          ),
          const Text(
            'Some servers do not expose file size immediately; ETA shows a dash until known.',
          ),
          const Text(
            'For Real-Debrid errors, verify your token and check host status on the RD dashboard.',
          ),
          const Text(
            'yt-dlp must be installed and available on PATH for the "Add via yt-dlp" feature.',
          ),
          const Text(
            'Use Export Links to back up your link list before clearing the queue.',
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Help'),
      content: SizedBox(
        width: 600,
        height: 440,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Getting Started'),
                Tab(text: 'Controls'),
                Tab(text: 'Settings'),
                Tab(text: 'Troubleshooting'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _overviewTab(),
                  _gettingStartedTab(),
                  _controlsTab(),
                  _settingsTab(),
                  _troubleshootingTab(),
                ],
              ),
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

class _HelpSection {
  const _HelpSection({
    this.title,
    required this.items,
    this.bulleted = false,
    this.ordered = false,
  });

  final String? title;
  final List<Widget> items;
  final bool bulleted;
  final bool ordered;
}

/// Convenience helper to show the [HelpDialogWidget].
Future<void> showHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const HelpDialogWidget(),
  );
}
