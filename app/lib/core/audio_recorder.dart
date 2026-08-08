// Gravador de áudio multiplataforma. No web usa o MediaRecorder do navegador;
// no celular, o pacote record (Opus/OGG quando o aparelho suporta).
export 'recorded_audio.dart';
export 'audio_recorder_io.dart' if (dart.library.js_interop) 'audio_recorder_web.dart';
