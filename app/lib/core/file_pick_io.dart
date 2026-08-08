import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
// O image_picker exporta um PickedFile legado (obsoleto) que colidiria com o
// nosso — esconde para o nome continuar sendo o do app.
import 'package:image_picker/image_picker.dart' hide PickedFile;

import 'picked_file.dart';

/// Seletor de arquivo nativo (Android/iOS). Documento pelo seletor do sistema;
/// foto pela câmera ou galeria — ver [pickImage].
Future<PickedFile?> pickFile({String? accept}) async {
  // Sem grupo de tipos = qualquer arquivo. O atendente precisa mandar boleto
  // (PDF), planilha, áudio… restringir aqui só atrapalharia.
  final XFile? f = await openFile();
  return f == null ? null : _toPicked(f);
}

/// Foto: pela câmera (`fromCamera`) ou pela galeria. Separado do [pickFile]
/// porque no celular são dois botões distintos no menu de anexo.
Future<PickedFile?> pickImage({bool fromCamera = false}) async {
  final XFile? f = await ImagePicker().pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    // Comprime antes de subir: foto de 12 MP no 4G do técnico em campo levaria
    // uma eternidade, e a Meta rejeita mídia acima de 5 MB.
    imageQuality: 82,
    maxWidth: 1920,
  );
  return f == null ? null : _toPicked(f);
}

Future<PickedFile> _toPicked(XFile f) async {
  final bytes = await f.readAsBytes();
  return PickedFile(
    name: f.name,
    bytes: Uint8List.fromList(bytes),
    mimeType: f.mimeType ?? _guessMime(f.name),
  );
}

/// Deduz o tipo pela extensão. O XFile do Android costuma vir com mimeType
/// nulo, e o backend precisa do tipo certo para a Meta aceitar o anexo.
String _guessMime(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'zip' => 'application/zip',
    'mp4' => 'video/mp4',
    'mp3' => 'audio/mpeg',
    'ogg' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    _ => 'application/octet-stream',
  };
}
