// Player de áudio inline da bolha. No web usa um <audio controls> nativo
// (play/pause/scrub do navegador, sem libs); em outras plataformas, stub.
export 'audio_view_stub.dart' if (dart.library.js_interop) 'audio_view_web.dart';
