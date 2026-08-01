// Empurra o compositor do navegador a apresentar o frame atual (contorna o
// "stale frame" do CanvasKit ao trocar de tema). Só faz algo no web.
export 'force_present_stub.dart' if (dart.library.js_interop) 'force_present_web.dart';
