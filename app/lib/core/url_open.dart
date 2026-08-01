// Abre uma URL externa. No web abre uma nova aba; em outras plataformas, noop.
export 'url_open_stub.dart' if (dart.library.js_interop) 'url_open_web.dart';
