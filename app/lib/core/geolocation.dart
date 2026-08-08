// Localização atual do dispositivo. No web usa a Geolocation API do navegador;
// no celular, o geolocator. Retorna (latitude, longitude) ou null.
export 'geolocation_io.dart' if (dart.library.js_interop) 'geolocation_web.dart';
