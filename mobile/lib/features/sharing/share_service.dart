import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Renders whatever's under [boundaryKey] (a RepaintBoundary) to a PNG and
/// hands it to the OS share sheet. Callers render the card off-screen (a
/// preview sheet) first, so the user sees exactly what they're about to
/// share rather than sharing blind.
Future<void> shareWidgetAsImage({
  required GlobalKey boundaryKey,
  required String filename,
  String? text,
}) async {
  final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename.png');
  await file.writeAsBytes(bytes);

  await Share.shareXFiles([XFile(file.path)], text: text);
}
