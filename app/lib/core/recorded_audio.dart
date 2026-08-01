import 'dart:typed_data';

/// Um áudio gravado no navegador, pronto para enviar.
class RecordedAudio {
  RecordedAudio({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}
