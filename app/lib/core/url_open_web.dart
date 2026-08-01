import 'package:web/web.dart' as web;

/// Abre a URL numa nova aba do navegador.
void openUrl(String url) {
  web.window.open(url, '_blank');
}
