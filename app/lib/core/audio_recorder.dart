// Gravador de áudio multiplataforma. No web usa o MediaRecorder do navegador;
// em outras plataformas, stub (o app roda em Flutter Web por ora).
export 'recorded_audio.dart';
export 'audio_recorder_stub.dart' if (dart.library.js_interop) 'audio_recorder_web.dart';
