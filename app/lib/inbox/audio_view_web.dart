import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Guarda os viewTypes já registrados (um por URL — as URLs são únicas).
final Set<String> _registered = {};

/// Cache do WIDGET por URL: devolver a MESMA instância faz o Flutter reconciliar
/// sem reconstruir a platform view (<audio>) — evita o jank ao trocar de tema.
final Map<String, Widget> _cache = {};

/// Devolve um player de áudio nativo do navegador (<audio controls>) para a URL.
Widget audioView(String url) {
  return _cache.putIfAbsent(url, () {
    final viewType = 'zap-audio::$url';
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final el = web.document.createElement('audio') as web.HTMLAudioElement;
        el.src = url;
        el.controls = true;
        el.preload = 'metadata';
        el.style.width = '100%';
        el.style.height = '40px';
        el.style.outline = 'none';
        return el;
      });
    }
    return SizedBox(
      width: 250,
      height: 44,
      child: HtmlElementView(viewType: viewType),
    );
  });
}
