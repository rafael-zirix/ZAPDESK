import 'package:geolocator/geolocator.dart';

/// Localização atual no celular. Retorna (latitude, longitude) ou null quando o
/// GPS está desligado ou a permissão foi negada — a tela trata como "não deu"
/// e avisa o atendente, sem travar o envio da conversa.
Future<(double, double)?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return (p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}
