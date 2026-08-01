import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// Abre o seletor de arquivo do navegador e devolve o arquivo escolhido.
/// Implementação nativa (package:web) — não remove o input antes do diálogo
/// abrir (o bug do file_picker v11 no web).
Future<PickedFile?> pickFile({String? accept}) {
  final completer = Completer<PickedFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept ?? 'image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt,.csv,.zip';
  input.style.display = 'none';

  void finish(PickedFile? f) {
    if (!completer.isCompleted) completer.complete(f);
    input.remove();
  }

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final buf = reader.result as JSArrayBuffer?;
      if (buf == null) {
        finish(null);
        return;
      }
      final bytes = buf.toDart.asUint8List();
      final mime = file.type.isNotEmpty ? file.type : 'application/octet-stream';
      finish(PickedFile(name: file.name, bytes: Uint8List.fromList(bytes), mimeType: mime));
    }.toJS;
    reader.onerror = ((web.Event _) => finish(null)).toJS;
    reader.readAsArrayBuffer(file);
  }.toJS;

  web.document.body!.appendChild(input);
  input.click(); // input permanece no DOM até o change/erro
  return completer.future;
}
