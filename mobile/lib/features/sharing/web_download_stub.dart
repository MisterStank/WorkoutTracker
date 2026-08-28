import 'dart:typed_data';

/// Non-web platforms never call this — the conditional import in
/// share_service.dart picks the real implementation only on web.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  throw UnsupportedError('downloadBytes is web-only');
}
