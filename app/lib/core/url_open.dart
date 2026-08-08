// Abre uma URL externa. No web, nova aba; no celular, o app do sistema
// (navegador, visualizador de PDF, mapa).
export 'url_open_io.dart' if (dart.library.js_interop) 'url_open_web.dart';
