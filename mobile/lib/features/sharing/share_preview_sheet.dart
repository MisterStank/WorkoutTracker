import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'share_service.dart';

/// Shows [card] in a bottom sheet with Download / Share actions — the user
/// sees exactly what image is about to go out (or be saved) before
/// anything happens.
Future<void> showSharePreview(BuildContext context, {required Widget card, required String filename, String? text}) {
  final boundaryKey = GlobalKey();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      Future<void> run(Future<void> Function() action, String failVerb) async {
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        try {
          await action();
          if (navigator.canPop()) navigator.pop();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Could not $failVerb the image: $e')));
        }
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: RepaintBoundary(key: boundaryKey, child: card),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => run(
                  () => downloadWidgetAsImage(boundaryKey: boundaryKey, filename: filename),
                  'save',
                ),
                icon: const Icon(Icons.download),
                label: Text(kIsWeb ? 'Download image' : 'Save image'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => run(
                  () => shareWidgetAsImage(boundaryKey: boundaryKey, filename: filename, text: text),
                  'share',
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share…'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
