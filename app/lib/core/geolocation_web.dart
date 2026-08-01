import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Pede a localização atual ao navegador. Retorna (latitude, longitude) ou null
/// (permissão negada / erro / sem suporte).
Future<(double, double)?> currentPosition() {
  final c = Completer<(double, double)?>();
  try {
    web.window.navigator.geolocation.getCurrentPosition(
      (web.GeolocationPosition p) {
        c.complete((p.coords.latitude.toDouble(), p.coords.longitude.toDouble()));
      }.toJS,
      (web.GeolocationPositionError _) {
        c.complete(null);
      }.toJS,
    );
  } catch (_) {
    c.complete(null);
  }
  return c.future;
}
