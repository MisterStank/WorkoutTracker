import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'web_download.dart' if (dart.library.io) 'web_download_stub.dart';

/// Rasterises whatever's under [boundaryKey] (a RepaintBoundary) to PNG
/// bytes at 3x for crisp output on any screen.
Future<Uint8List> _renderPng(GlobalKey boundaryKey) async {
  final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Hands the rendered card to the OS share sheet (native apps) or the Web
/// Share API (browsers that support sharing files — mainly mobile).
Future<void> shareWidgetAsImage({
  required GlobalKey boundaryKey,
  required String filename,
  String? text,
}) async {
  final bytes = await _renderPng(boundaryKey);

  if (kIsWeb) {
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: '$filename.png', mimeType: 'image/png')],
      text: text,
    );
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename.png');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path)], text: text);
}

/// Saves the rendered card as a file the user keeps: a browser download on
/// web, and — since native gallery-save needs an extra plugin the app
/// doesn't carry — the OS share sheet (which offers "Save Image" / "Save to
/// Files") on iOS/Android.
Future<void> downloadWidgetAsImage({
  required GlobalKey boundaryKey,
  required String filename,
}) async {
  final bytes = await _renderPng(boundaryKey);

  if (kIsWeb) {
    downloadBytes(bytes, '$filename.png', 'image/png');
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename.png');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path)]);
}
