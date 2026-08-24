import 'package:flutter/material.dart';

import 'share_service.dart';

/// Shows [card] in a bottom sheet with a Share button — the user sees
/// exactly what image is about to go out before it's handed to the OS
/// share sheet.
Future<void> showSharePreview(BuildContext context, {required Widget card, required String filename, String? text}) {
  final boundaryKey = GlobalKey();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
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
                onPressed: () => shareWidgetAsImage(boundaryKey: boundaryKey, filename: filename, text: text),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
