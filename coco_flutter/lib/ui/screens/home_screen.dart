/// HomeScreen — the single-page layout for Coco Downloader.
///
/// Implements a 3-zone design inside a [Scaffold]:
///   Zone 1 (top)    — [InputZone]: single/bulk link input with drag-and-drop.
///   Zone 2 (centre) — [FilterBar] + [PreviewTable]: expandable download queue.
///   Zone 3 (bottom) — [ActionBar]: save path, connections, progress, controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../widgets/action_bar.dart';
import '../widgets/filter_bar.dart';
import '../widgets/input_zone.dart';
import '../widgets/preview_table.dart';

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: const _HomeBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// _HomeBody
// ---------------------------------------------------------------------------

/// Three-zone layout using a [Column].
///
/// Zone 2 is wrapped in [Expanded] so the preview table claims all remaining
/// vertical space after zones 1 and 3 have been laid out.
class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        // Zone 1 — Link input
        InputZone(),

        Divider(height: 1),

        // Zone 2 — Filter controls + preview table (takes all remaining space)
        FilterBar(),
        Expanded(
          child: PreviewTable(),
        ),

        Divider(height: 1),

        // Zone 3 — Action bar (path, connections, progress, buttons, log)
        ActionBar(),
      ],
    );
  }
}
