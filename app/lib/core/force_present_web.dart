import 'dart:async';

import 'package:web/web.dart' as web;

/// Força o navegador a COMPOR/apresentar o frame atual do CanvasKit — contorna o
/// "stale frame" (a tela congela no estado intermediário até um input real).
/// Mimetiza o que destrava na prática: redimensionar a janela / mexer o mouse.
void nudgeCompositor() {
  // 1) 'resize' → o Flutter re-mede a view e agenda um novo frame.
  web.window.dispatchEvent(web.Event('resize'));

  // 2) Toque de camada no host do Flutter: promover a uma layer de composição
  //    (translateZ(0), sem efeito visual) e reverter força o navegador a
  //    apresentar o canvas WebGL parado.
  final host = (web.document.querySelector('flutter-view') ??
      web.document.querySelector('flt-glass-pane') ??
      web.document.body) as web.HTMLElement?;
  if (host == null) return;
  final original = host.style.transform;
  host.style.transform = 'translateZ(0)';
  Timer(const Duration(milliseconds: 32), () => host.style.transform = original);
}

/// Recarrega a página. Forma 100% confiável de aplicar o tema no ambiente do
/// usuário (Chrome + Skia Graphite): a troca ao vivo congela no stale frame do
/// CanvasKit, mas ao recarregar o app lê a preferência e já pinta na cor certa.
void reloadApp() {
  web.window.location.reload();
}
