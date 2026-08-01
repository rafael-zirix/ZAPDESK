import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'recorded_audio.dart';

/// Gravador de áudio do navegador (MediaRecorder). Uma instância por painel.
/// Grava normalmente em audio/webm;codecs=opus (Chrome) — o backend converte
/// para audio/ogg (opus) antes de mandar à Meta, para virar mensagem de voz.
class AudioRecorder {
  web.MediaRecorder? _rec;
  web.MediaStream? _stream;
  final List<web.Blob> _chunks = [];

  /// Pede o microfone e começa a gravar. Retorna false se negado/erro.
  Future<bool> start() async {
    try {
      _chunks.clear();
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      final stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
      _stream = stream;
      final rec = web.MediaRecorder(stream);
      rec.ondataavailable = (web.Event e) {
        final data = (e as web.BlobEvent).data;
        if (data.size > 0) _chunks.add(data);
      }.toJS;
      rec.start();
      _rec = rec;
      return true;
    } catch (_) {
      _cleanup();
      return false;
    }
  }

  /// Para a gravação e devolve o áudio (null se nada foi capturado).
  Future<RecordedAudio?> stop() async {
    final rec = _rec;
    if (rec == null) return null;
    final done = Completer<RecordedAudio?>();
    rec.onstop = (web.Event _) {
      final type = rec.mimeType.isNotEmpty ? rec.mimeType : 'audio/webm';
      final blob = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: type));
      blob.arrayBuffer().toDart.then((buf) {
        final bytes = buf.toDart.asUint8List();
        _cleanup();
        done.complete(RecordedAudio(bytes: Uint8List.fromList(bytes), mimeType: type));
      });
    }.toJS;
    try {
      rec.stop();
    } catch (_) {
      _cleanup();
      return null;
    }
    return done.future;
  }

  /// Cancela e descarta o que estava gravando.
  void cancel() {
    try {
      _rec?.stop();
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    final s = _stream;
    if (s != null) {
      final tracks = s.getTracks().toDart;
      for (final t in tracks) {
        t.stop();
      }
    }
    _rec = null;
    _stream = null;
    _chunks.clear();
  }
}
