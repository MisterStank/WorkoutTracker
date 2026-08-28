import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// `web` is already a transitive dependency (pulled in by Flutter itself); this
// file is the only place that touches it directly, so an ignore is lighter
// than a pubspec entry + lockfile churn.
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Triggers a browser download of [bytes] as [filename] by creating a
/// short-lived object URL and clicking a synthetic anchor. The URL is
/// revoked a beat later — revoking it immediately after click() races the
/// browser and can cancel the download in some engines.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  Timer(const Duration(seconds: 1), () {
    anchor.remove();
    web.URL.revokeObjectURL(url);
  });
}
