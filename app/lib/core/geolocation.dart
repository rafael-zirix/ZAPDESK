// Localização atual do dispositivo. No web usa a Geolocation API do navegador;
// em outras plataformas, stub. Retorna (latitude, longitude) ou null.
export 'geolocation_stub.dart' if (dart.library.js_interop) 'geolocation_web.dart';
