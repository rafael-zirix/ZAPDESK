import 'package:url_launcher/url_launcher.dart';

/// Abre a URL no app externo (navegador, visualizador de PDF, mapa). Silencioso
/// em caso de falha: um documento que não abre não pode derrubar a conversa.
void openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
}
