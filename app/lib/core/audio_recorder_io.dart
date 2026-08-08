import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;

import 'recorded_audio.dart';

/// Gravador de áudio nativo (Android/iOS) — a mesma interface da versão web,
/// para a tela de conversa não saber em que plataforma está.
///
/// Grava em Opus/OGG quando o aparelho suporta: é o formato que a Meta aceita
/// como MENSAGEM DE VOZ (aquela com a onda e o play). Caindo no AAC, o áudio
/// chega como anexo comum — funciona, mas perde a cara de WhatsApp.
class AudioRecorder {
  final _rec = rec.AudioRecorder();
  String? _path;

  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) return false;
      final opus = await _rec.isEncoderSupported(rec.AudioEncoder.opus);
      final encoder = opus ? rec.AudioEncoder.opus : rec.AudioEncoder.aacLc;
      final dir = await getTemporaryDirectory();
      // Nome fixo: grava um áudio por vez e o arquivo morre no envio.
      _path = '${dir.path}/hotzap_rec.${opus ? 'ogg' : 'm4a'}';
      await _rec.start(rec.RecordConfig(encoder: encoder), path: _path!);
      return true;
    } catch (_) {
      _path = null;
      return false;
    }
  }

  Future<RecordedAudio?> stop() async {
    try {
      final path = await _rec.stop();
      _path = null;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      if (bytes.isEmpty) return null;
      return RecordedAudio(
        bytes: bytes,
        mimeType: path.endsWith('.ogg') ? 'audio/ogg' : 'audio/mp4',
      );
    } catch (_) {
      return null;
    }
  }

  void cancel() {
    _rec.cancel().catchError((_) => null);
    final p = _path;
    _path = null;
    if (p != null) {
      // Descarta o parcial; o áudio cancelado não deve sobrar no aparelho.
      File(p).delete().catchError((_) => File(p));
    }
  }
}
