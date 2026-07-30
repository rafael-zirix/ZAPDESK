import 'dart:typed_data';

/// Arquivo escolhido pelo usuário (foto/documento).
class PickedFile {
  PickedFile({required this.name, required this.bytes, required this.mimeType});
  final String name;
  final Uint8List bytes;
  final String mimeType;
}
